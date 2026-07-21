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

import Foundation
import Logging

/// The step loop behind ``OCIMetricsFactory``: snapshots ``OCIMetricsRegistry`` on a fixed cadence
/// and posts the result through ``MonitoringClient``.
///
/// The actor owns everything that must not be touched concurrently — the retry buffer, the
/// statistics, the step task — while the recording hot path stays entirely outside it, in the
/// `Mutex`-guarded handlers. Nothing here is called from the application's threads.
///
/// ## Lifecycle
///
/// ``start()`` launches one long-lived task that alternates a cancellation-cooperative
/// `Task.sleep(for:)` with a flush; ``shutdown()`` cancels it and drains what is left. The task
/// retains the exporter, so a factory that is started must eventually be shut down — dropping the
/// last reference is not enough to stop it.
///
/// Concurrent ``flush()`` calls are coalesced onto a single in-flight flush (the
/// ``OKEWorkloadIdentitySigner`` idiom), so an explicit flush that races the step tick cannot
/// double-post a snapshot.
///
/// ## What a flush does
///
/// 1. Drains the registry and turns each stream into a ``MetricDataDetails``, timestamped at the
///    instant of the snapshot.
/// 2. Appends anything the previous flush could not deliver, bounding the buffer.
/// 3. Drops data points older than ``maximumDatapointAge`` — the service refuses them, so carrying
///    them further would poison every retry.
/// 4. Splits the result into requests of at most ``maximumStreamsPerRequest`` streams and posts
///    them, reading ``PostMetricDataResponseDetails/failedMetrics`` out of each `200`.
///
/// Nothing on this path throws: a metrics backend that can take its application down is worse than
/// one that loses a step. Every loss is counted in ``OCIMetricsStatistics``.
actor OCIMetricsExporter {
  /// The service's per-request limit on unique metric streams. A 51st stream fails the whole
  /// request with `400` `"The valid range is 1 to 50"` (live-verified).
  static let maximumStreamsPerRequest = 50

  /// The service's staleness window. Data points older than this are rejected with
  /// `"The datapoint timestamps must be between 2 hours ago and 10 minutes from now."`
  /// (live-verified), which makes two hours the backend's entire outage budget.
  static let maximumDatapointAge: TimeInterval = 2 * 60 * 60

  private let client: MonitoringClient
  private let configuration: OCIMetricsConfiguration
  private let registry: OCIMetricsRegistry
  private let logger: Logger

  /// Streams whose request failed and that will be re-posted on the next flush.
  private var buffered: [MetricDataDetails] = []
  /// The running tally returned by ``statistics()``.
  private var tally = OCIMetricsStatistics()
  /// The step loop, `nil` until ``start()`` and after ``shutdown()``.
  private var stepTask: Task<Void, Never>?
  /// The flush currently running, used to coalesce concurrent flushes.
  private var inFlightFlush: Task<Void, Never>?

  /// Creates an exporter.
  ///
  /// - Parameters:
  ///   - client: The Monitoring ingestion client used to post. Inject one built with a stub
  ///     ``HTTPClient`` to exercise the exporter without a tenancy.
  ///   - configuration: The wire mapping, step and buffer bounds.
  ///   - registry: The registry to snapshot.
  ///   - logger: Logger for export diagnostics.
  init(
    client: MonitoringClient,
    configuration: OCIMetricsConfiguration,
    registry: OCIMetricsRegistry,
    logger: Logger
  ) {
    self.client = client
    self.configuration = configuration
    self.registry = registry
    self.logger = logger
  }

  // MARK: - Lifecycle

  /// Starts the periodic step loop. Calling it again while the loop runs does nothing.
  func start() {
    guard stepTask == nil else { return }
    let step = configuration.step
    stepTask = Task {
      while !Task.isCancelled {
        do { try await Task.sleep(for: step) }
        catch { return }  // cancelled — shutdown() takes it from here
        await self.flush()
      }
    }
  }

  /// Stops the step loop and posts everything still held.
  ///
  /// Waits for a flush that is already running before draining, so no step is lost and no snapshot
  /// is posted twice.
  func shutdown() async {
    stepTask?.cancel()
    stepTask = nil
    if let inFlightFlush { await inFlightFlush.value }
    await flush()
  }

  /// Snapshots the registry and posts, coalescing with a flush that is already in progress.
  func flush() async {
    if let inFlightFlush {
      await inFlightFlush.value
      return
    }
    let flush = Task { await self.performFlush() }
    inFlightFlush = flush
    await flush.value
  }

  /// The running tally of what has been published and what has been lost.
  func statistics() -> OCIMetricsStatistics { tally }

  // MARK: - Flushing

  private func performFlush() async {
    defer { inFlightFlush = nil }

    let now = Date()
    let drained = registry.drain()
    tally.droppedSamples += drained.droppedSamples

    var queue = buffered
    buffered = []
    queue.append(contentsOf: drained.snapshots.map { configuration.metricData(for: $0, at: now) })

    if queue.count > configuration.maximumBufferedStreams {
      let overflow = queue.count - configuration.maximumBufferedStreams
      queue.removeFirst(overflow)
      tally.droppedBufferedStreams += overflow
      logger.warning("[OCIMetricsExporter] dropped \(overflow) buffered metric stream(s): buffer is full")
    }

    let pruned = Self.pruningStaleDatapoints(queue, now: now)
    if pruned.droppedDatapoints > 0 {
      tally.droppedStaleDatapoints += pruned.droppedDatapoints
      logger.warning(
        "[OCIMetricsExporter] dropped \(pruned.droppedDatapoints) datapoint(s) older than the service's 2-hour window"
      )
    }
    guard !pruned.metrics.isEmpty else { return }

    var retry: [MetricDataDetails] = []
    for chunk in Self.chunked(pruned.metrics, maximumStreamsPerRequest: Self.maximumStreamsPerRequest) {
      do {
        let response = try await client.postMetricData(details: PostMetricDataDetails(metricData: chunk))
        account(response, for: chunk)
      }
      catch {
        tally.failedRequests += 1
        retry.append(contentsOf: chunk)
        logger.warning("[OCIMetricsExporter] postMetricData failed for \(chunk.count) stream(s): \(error)")
      }
    }
    buffered = retry
  }

  /// Folds one `200` response into the tally, logging whatever the service rejected.
  ///
  /// Rejections are permanent — the metric object violated an input rule — so they are counted and
  /// dropped rather than buffered for a retry that would fail identically.
  private func account(_ response: PostMetricDataResponseDetails, for chunk: [MetricDataDetails]) {
    let failed = response.failedMetrics ?? []
    tally.failedMetrics += response.failedMetricsCount
    tally.postedStreams += max(0, chunk.count - response.failedMetricsCount)
    let sentDatapoints = chunk.reduce(0) { $0 + $1.datapoints.count }
    let failedDatapoints = failed.reduce(0) { $0 + $1.metricData.datapoints.count }
    tally.postedDatapoints += max(0, sentDatapoints - failedDatapoints)

    guard response.failedMetricsCount > 0 else { return }
    for record in failed {
      logger.warning("[OCIMetricsExporter] metric \"\(record.metricData.name)\" rejected: \(record.message)")
    }
    if failed.isEmpty {
      logger.warning("[OCIMetricsExporter] \(response.failedMetricsCount) metric stream(s) rejected by the service")
    }
  }
}

// MARK: - Pure wire helpers

extension OCIMetricsExporter {
  /// Splits metric objects into requests of at most `limit` streams.
  ///
  /// - Parameters:
  ///   - metrics: The metric objects to post, already ordered deterministically by the registry.
  ///   - limit: The maximum number of streams per request.
  /// - Returns: The requests to send, in order. Empty when there is nothing to post.
  static func chunked(_ metrics: [MetricDataDetails], maximumStreamsPerRequest limit: Int) -> [[MetricDataDetails]] {
    guard !metrics.isEmpty else { return [] }
    guard limit > 0, metrics.count > limit else { return [metrics] }
    return stride(from: 0, to: metrics.count, by: limit).map { start in
      Array(metrics[start..<min(start + limit, metrics.count)])
    }
  }

  /// Drops the data points the service would refuse for being too old, and the metric objects left
  /// with none.
  ///
  /// - Parameters:
  ///   - metrics: The metric objects about to be posted.
  ///   - now: The instant to measure staleness against.
  /// - Returns: The metric objects still worth posting, and how many data points were dropped.
  static func pruningStaleDatapoints(
    _ metrics: [MetricDataDetails],
    now: Date
  ) -> (metrics: [MetricDataDetails], droppedDatapoints: Int) {
    let cutoff = now.addingTimeInterval(-maximumDatapointAge)
    var kept: [MetricDataDetails] = []
    kept.reserveCapacity(metrics.count)
    var dropped = 0

    for metric in metrics {
      let fresh = metric.datapoints.filter { $0.timestamp > cutoff }
      if fresh.count == metric.datapoints.count {
        kept.append(metric)
        continue
      }
      dropped += metric.datapoints.count - fresh.count
      guard !fresh.isEmpty else { continue }
      kept.append(
        MetricDataDetails(
          namespace: metric.namespace,
          resourceGroup: metric.resourceGroup,
          compartmentId: metric.compartmentId,
          name: metric.name,
          dimensions: metric.dimensions,
          metadata: metric.metadata,
          datapoints: fresh
        )
      )
    }
    return (kept, dropped)
  }
}
