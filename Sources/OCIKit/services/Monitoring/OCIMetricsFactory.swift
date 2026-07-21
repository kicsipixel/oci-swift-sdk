//===----------------------------------------------------------------------===//
//
// This source file is part of the oci-swift-sdk open source project
//
// Copyright (c) 2026 Ilia Sazonov and the oci-swift-sdk project authors
// Licensed under MIT License
//
// See LICENSE for license information
// See CONTRIBUTORS.md for the list of oci-swift-sdk project authors
//
// SPDX-License-Identifier: MIT License
//
//===----------------------------------------------------------------------===//

import CoreMetrics
import Foundation
import Logging

/// A [swift-metrics](https://github.com/apple/swift-metrics) backend that publishes an
/// application's metrics to OCI Monitoring.
///
/// Metrics recorded through the swift-metrics API — `Counter`, `Gauge`, `Recorder`, `Timer`,
/// `Meter`, and the `FloatingPointCounter` — are aggregated in process and posted to
/// ``MonitoringClient/postMetricData(details:opcRequestId:)`` on a fixed step (60 seconds by
/// default), which is how Oracle's own Micronaut and Helidon integrations publish custom metrics.
/// From there they are queryable, chartable and alarmable next to the platform's `oci_*` metrics.
///
/// ## Composition
///
/// The SDK never calls `MetricsSystem.bootstrap` — process-global systems belong to the
/// application, which may well want to multiplex this backend with another one:
///
/// ```swift
/// import CoreMetrics
/// import OCIKit
///
/// let signer = try APIKeySigner(configFilePath: "~/.oci/config")
/// let client = try MonitoringClient(region: .phx, signer: signer)
/// let factory = try OCIMetricsFactory(
///   client: client,
///   configuration: OCIMetricsConfiguration(
///     namespace: "my_app",
///     compartmentId: compartmentId,
///     commonDimensions: ["service": "checkout", "env": "prod"]
///   )
/// )
/// await factory.start()
/// MetricsSystem.bootstrap(factory)
///
/// // ... and at the end of the process's life, so the last step is not lost:
/// await factory.shutdown()
/// ```
///
/// ## Design
///
/// - **Recording never blocks.** The handler classes write into `Mutex`-guarded storage
///   (`Synchronization`); the lock is never held across an `await`, no task is spawned per
///   observation, and nothing allocates beyond the accumulator itself.
/// - **Exporting is one actor.** ``OCIMetricsExporter`` owns a single cancellation-cooperative
///   `Task.sleep(for:)` loop, coalesces concurrent flushes, and is the only thing that talks to the
///   network. The step task retains the exporter, so ``shutdown()`` — not deallocation — is what
///   stops it.
/// - **The wire rules are enforced here, not by the caller.** Requests are split at 50 unique
///   streams, dimension keys and values are sanitized, a default dimension is synthesized for
///   metrics that have none (the service rejects an empty map), and data points that have aged past
///   the service's two-hour window are dropped rather than retried forever.
/// - **Losses are counted, never thrown.** Nothing on the export path can take the application
///   down; ``statistics()`` reports what was published and what was lost.
///
/// ## Aggregation
///
/// | Instrument | Posted per step |
/// |---|---|
/// | `Counter` | One data point: the delta accumulated since the previous step. Untouched steps post nothing. |
/// | `FloatingPointCounter` | As `Counter` — swift-metrics accumulates the fraction and forwards whole increments. |
/// | `Recorder` | One data point per distinct value observed, carrying its occurrence count. |
/// | `Gauge` | One data point: the most recent value, repeated every step until it changes. |
/// | `Meter` | As `Recorder` — swift-metrics' default meter wrapper records every `set`/`increment` into an aggregating recorder, so a step nobody touched posts nothing. |
/// | `Timer` | As `Recorder`, in **nanoseconds**, with `metadata` `["unit": "ns"]`. |
///
/// Only `makeCounter`, `makeRecorder` and `makeTimer` are implemented; `Meter` and
/// `FloatingPointCounter` are served by swift-metrics' protocol-provided wrappers, which is why
/// they inherit the aggregation of the instrument they wrap.
public final class OCIMetricsFactory: MetricsFactory {
  /// How swift-metrics instruments are mapped onto OCI Monitoring metric objects.
  public let configuration: OCIMetricsConfiguration

  private let registry: OCIMetricsRegistry
  private let exporter: OCIMetricsExporter

  /// Creates a metrics backend.
  ///
  /// The step loop does not run until ``start()`` is called, so a factory can be constructed and
  /// bootstrapped before the application is ready to talk to the network.
  ///
  /// - Parameters:
  ///   - client: The Monitoring ingestion client used to publish. Its signer's principal needs
  ///     `allow ... to use metrics in compartment ...`, optionally narrowed with
  ///     `where target.metrics.namespace='<namespace>'`.
  ///   - configuration: The namespace, compartment, dimensions, step and buffer bounds.
  ///   - logger: Logger for export diagnostics. Defaults to a logger labelled `OCIMetricsFactory`.
  public init(
    client: MonitoringClient,
    configuration: OCIMetricsConfiguration,
    logger: Logger = Logger(label: "OCIMetricsFactory")
  ) {
    self.configuration = configuration
    self.registry = OCIMetricsRegistry(configuration: configuration)
    self.exporter = OCIMetricsExporter(
      client: client,
      configuration: configuration,
      registry: registry,
      logger: logger
    )
  }

  // MARK: - Lifecycle

  /// Starts publishing on ``OCIMetricsConfiguration/step``.
  ///
  /// Calling it again while the loop runs does nothing. The loop retains the backend until
  /// ``shutdown()`` is called.
  public func start() async {
    await exporter.start()
  }

  /// Snapshots every live instrument and publishes immediately, without disturbing the step
  /// cadence.
  ///
  /// A flush that races the step tick is coalesced onto it rather than posting the same snapshot
  /// twice. Returns once the publish has completed — successfully or not; failures are counted in
  /// ``statistics()``.
  public func flush() async {
    await exporter.flush()
  }

  /// Stops the step loop and publishes everything still held.
  ///
  /// Call this before the process exits, otherwise up to one step's worth of metrics is lost — and
  /// the step task keeps the backend alive.
  public func shutdown() async {
    await exporter.shutdown()
  }

  /// The running tally of what has been published and what has been lost.
  ///
  /// - Returns: A snapshot of ``OCIMetricsStatistics``.
  public func statistics() async -> OCIMetricsStatistics {
    await exporter.statistics()
  }

  // MARK: - MetricsFactory

  /// Returns the handler backing a `Counter` with this label and these dimensions, creating it on
  /// first use.
  ///
  /// - Parameters:
  ///   - label: The metric name.
  ///   - dimensions: The metric's dimensions, as `(name, value)` tuples.
  /// - Returns: The shared handler for that stream.
  public func makeCounter(label: String, dimensions: [(String, String)]) -> CounterHandler {
    registry.counter(id: OCIMetricsStreamID(kind: .counter, label: label, dimensions: dimensions))
  }

  /// Returns the handler backing a `Recorder` or `Gauge` with this label and these dimensions,
  /// creating it on first use.
  ///
  /// - Parameters:
  ///   - label: The metric name.
  ///   - dimensions: The metric's dimensions, as `(name, value)` tuples.
  ///   - aggregate: `true` for a `Recorder` (every value of the step is published), `false` for a
  ///     `Gauge` (the last value is published, and repeated until it changes).
  /// - Returns: The shared handler for that stream.
  public func makeRecorder(label: String, dimensions: [(String, String)], aggregate: Bool) -> RecorderHandler {
    let id = OCIMetricsStreamID(kind: aggregate ? .recorder : .gauge, label: label, dimensions: dimensions)
    return registry.recorder(id: id, aggregate: aggregate)
  }

  /// Returns the handler backing a `Timer` with this label and these dimensions, creating it on
  /// first use.
  ///
  /// - Parameters:
  ///   - label: The metric name.
  ///   - dimensions: The metric's dimensions, as `(name, value)` tuples.
  /// - Returns: The shared handler for that stream.
  public func makeTimer(label: String, dimensions: [(String, String)]) -> TimerHandler {
    registry.timer(id: OCIMetricsStreamID(kind: .timer, label: label, dimensions: dimensions))
  }

  /// Unregisters a counter, keeping the values it recorded since the last step so they are still
  /// published.
  ///
  /// - Parameter handler: The handler swift-metrics is destroying.
  public func destroyCounter(_ handler: CounterHandler) {
    guard let handler = handler as? OCIMetricsCounterHandler else { return }
    registry.destroy(handler)
  }

  /// Unregisters a recorder or gauge, keeping the values it recorded since the last step so they
  /// are still published.
  ///
  /// - Parameter handler: The handler swift-metrics is destroying.
  public func destroyRecorder(_ handler: RecorderHandler) {
    guard let handler = handler as? OCIMetricsRecorderHandler else { return }
    registry.destroy(handler)
  }

  /// Unregisters a timer, keeping the durations it recorded since the last step so they are still
  /// published.
  ///
  /// - Parameter handler: The handler swift-metrics is destroying.
  public func destroyTimer(_ handler: TimerHandler) {
    guard let handler = handler as? OCIMetricsTimerHandler else { return }
    registry.destroy(handler)
  }
}
