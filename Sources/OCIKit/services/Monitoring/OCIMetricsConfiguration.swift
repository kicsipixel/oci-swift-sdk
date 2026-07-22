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

/// How ``OCIMetricsFactory`` maps swift-metrics instruments onto OCI Monitoring metric objects.
///
/// Everything the service needs but swift-metrics has no concept of — the namespace, the
/// compartment, the resource group — lives here, along with the two knobs that govern how much
/// memory the backend may use and how often it posts.
///
/// The initializer validates eagerly and throws, so a process that is going to be rejected by the
/// service fails at start-up rather than 60 seconds later on a background task nobody is watching.
///
/// ## Example
///
/// ```swift
/// let configuration = try OCIMetricsConfiguration(
///   namespace: "my_app",
///   compartmentId: compartmentId,
///   commonDimensions: ["service": "checkout", "env": "prod"]
/// )
/// ```
public struct OCIMetricsConfiguration: Sendable {
  /// The metadata key under which a timer's unit is published.
  static let unitMetadataKey = "unit"
  /// The metadata value published for timers, whose data points are nanosecond durations.
  static let nanosecondsUnit = "ns"
  /// The dimension key synthesized, by default, for metrics that end up with no dimensions at all.
  public static let fallbackDimensionName = "source"
  /// The dimension value used when the host name is unavailable or unusable.
  public static let fallbackDimensionValue = "unknown"

  /// The metric namespace every metric object is posted under.
  ///
  /// Validated against the service's rules — `^[a-z][a-z0-9_]*[a-z0-9]$` (lower case only), at most
  /// 256 characters, no `oci_` or `oracle_` prefix — when the configuration is created.
  public let namespace: String
  /// The OCID of the compartment metric data is posted to, billed against, and queried in.
  public let compartmentId: String
  /// The optional resource group every metric object is posted under.
  public let resourceGroup: String?
  /// Dimensions merged into every metric object, already sanitized.
  ///
  /// These describe the emitting workload — service name, environment, instance — rather than any
  /// one metric. On a key collision they **win** over the instrument's own dimensions: they are set
  /// by the operator and identify the resource, so an application label must not be able to shadow
  /// them.
  public let commonDimensions: [String: String]
  /// The key of the dimension synthesized for metrics that would otherwise have none.
  ///
  /// The service rejects a metric object with an empty `dimensions` map (`400` `"dimensions can not
  /// be null or empty"`, live-verified), and swift-metrics instruments are frequently created with
  /// no dimensions at all, so the backend must supply one.
  public let defaultDimensionName: String
  /// The value of the dimension synthesized for metrics that would otherwise have none.
  ///
  /// Defaults to the host name, which is what makes a label-less metric attributable to a machine
  /// once several replicas post into the same namespace.
  public let defaultDimensionValue: String
  /// How often the exporter snapshots the registry and posts.
  ///
  /// Defaults to 60 seconds, matching the step Oracle's own Micronaut and Helidon integrations use,
  /// and comfortably inside Monitoring's minimum aggregation interval of one minute.
  ///
  /// - Note: Spelled `Swift.Duration` because OCIKit ships as a single module and already exposes
  ///   an Object Storage lifecycle model named `Duration`.
  public let step: Swift.Duration
  /// The maximum number of metric streams held in the exporter's retry buffer.
  ///
  /// Streams whose request failed *transiently* are re-posted on the next step. Once the buffer is
  /// full the oldest are dropped and counted in ``OCIMetricsStatistics/droppedBufferedStreams`` —
  /// the backend bounds its own memory rather than growing without limit behind an outage.
  ///
  /// - Important: This bounds the **retry buffer only**. A step's fresh streams are always posted,
  ///   however many of them there are, so an application with more live instruments than this bound
  ///   loses nothing while the network is healthy.
  public let maximumBufferedStreams: Int
  /// The maximum number of distinct values a recorder or timer retains per step.
  ///
  /// Beyond this bound, repeats of an already-seen value still count but new distinct values are
  /// dropped and counted in ``OCIMetricsStatistics/droppedSamples``.
  public let maximumSamplesPerStream: Int

  /// Creates and validates a configuration.
  ///
  /// - Parameters:
  ///   - namespace: The metric namespace. Must match `^[a-z][a-z0-9_]*[a-z0-9]$` — the service
  ///     accepts lower case only — be at most 256 characters, and must not start with `oci_` or
  ///     `oracle_`.
  ///   - compartmentId: The OCID of the compartment to post metric data to. Must be non-empty.
  ///   - resourceGroup: The optional resource group to post every metric object under.
  ///   - commonDimensions: Dimensions merged into every metric object. Sanitized here, once.
  ///   - defaultDimensionName: The key of the dimension synthesized for metrics with no dimensions.
  ///     Defaults to `source`.
  ///   - defaultDimensionValue: The value of that dimension. Defaults to the host name.
  ///   - step: How often to snapshot and post. Defaults to 60 seconds.
  ///   - maximumBufferedStreams: The retry buffer bound. Defaults to 500 streams.
  ///   - maximumSamplesPerStream: The per-step distinct-value bound. Defaults to 1,000 values.
  ///
  /// - Throws: ``OCIMetricsError/invalidNamespace(_:)``,
  ///   ``OCIMetricsError/missingCompartmentId``, ``OCIMetricsError/invalidStep(_:)`` or
  ///   ``OCIMetricsError/invalidBufferBound(_:_:)`` when an argument cannot produce a legal
  ///   request.
  public init(
    namespace: String,
    compartmentId: String,
    resourceGroup: String? = nil,
    commonDimensions: [String: String] = [:],
    defaultDimensionName: String = OCIMetricsConfiguration.fallbackDimensionName,
    defaultDimensionValue: String = ProcessInfo.processInfo.hostName,
    step: Swift.Duration = .seconds(60),
    maximumBufferedStreams: Int = 500,
    maximumSamplesPerStream: Int = 1000
  ) throws {
    guard OCIMetricsSanitizer.isValidNamespace(namespace) else {
      throw OCIMetricsError.invalidNamespace(namespace)
    }
    guard !compartmentId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw OCIMetricsError.missingCompartmentId
    }
    guard step > Swift.Duration.zero else {
      throw OCIMetricsError.invalidStep(step)
    }
    guard maximumBufferedStreams > 0 else {
      throw OCIMetricsError.invalidBufferBound("maximumBufferedStreams", maximumBufferedStreams)
    }
    guard maximumSamplesPerStream > 0 else {
      throw OCIMetricsError.invalidBufferBound("maximumSamplesPerStream", maximumSamplesPerStream)
    }

    self.namespace = namespace
    self.compartmentId = compartmentId
    self.resourceGroup = resourceGroup
    self.commonDimensions = OCIMetricsSanitizer.dimensions(commonDimensions)
    self.defaultDimensionName =
      OCIMetricsSanitizer.dimensionKey(defaultDimensionName) ?? Self.fallbackDimensionName
    self.defaultDimensionValue =
      OCIMetricsSanitizer.dimensionValue(defaultDimensionValue) ?? Self.fallbackDimensionValue
    self.step = step
    self.maximumBufferedStreams = maximumBufferedStreams
    self.maximumSamplesPerStream = maximumSamplesPerStream
  }

  // MARK: - Wire mapping

  /// Resolves the dimensions posted for one stream.
  ///
  /// The instrument's own dimensions are sanitized, the common dimensions are merged over them, and
  /// — only if nothing at all survives — the default dimension is synthesized. The result is capped
  /// at the service's 20-dimension limit.
  ///
  /// - Parameter id: The stream whose dimensions to resolve.
  /// - Returns: A non-empty, service-legal dimension map.
  func dimensions(for id: OCIMetricsStreamID) -> [String: String] {
    var dimensions = OCIMetricsSanitizer.dimensions(id.dimensions)
    for (key, value) in commonDimensions { dimensions[key] = value }
    if dimensions.isEmpty { dimensions[defaultDimensionName] = defaultDimensionValue }
    return OCIMetricsSanitizer.capped(dimensions)
  }

  /// Turns one drained stream into the metric object posted for it.
  ///
  /// Every data point of a step carries the same `timestamp` — the instant the registry was
  /// snapshotted — because that is the instant the step's aggregation describes.
  ///
  /// - Parameters:
  ///   - snapshot: The step's samples for one stream.
  ///   - timestamp: The instant the registry was snapshotted.
  /// - Returns: The metric object to post.
  func metricData(for snapshot: OCIMetricsStreamSnapshot, at timestamp: Date) -> MetricDataDetails {
    MetricDataDetails(
      namespace: namespace,
      resourceGroup: resourceGroup,
      compartmentId: compartmentId,
      name: OCIMetricsSanitizer.metricName(snapshot.id.label),
      dimensions: dimensions(for: snapshot.id),
      metadata: snapshot.id.kind == .timer ? [Self.unitMetadataKey: Self.nanosecondsUnit] : nil,
      datapoints: snapshot.samples.map {
        MonitoringDatapoint(timestamp: timestamp, value: $0.value, count: $0.count)
      }
    )
  }
}
