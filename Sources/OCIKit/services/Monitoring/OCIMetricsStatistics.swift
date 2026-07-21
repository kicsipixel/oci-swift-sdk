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

/// A running tally of what ``OCIMetricsFactory`` has managed to publish — and what it has not.
///
/// A metrics backend must never take an application down, so nothing on the export path throws:
/// every loss is absorbed and counted here instead. Reading these counters through
/// ``OCIMetricsFactory/statistics()`` is the only way to find out that telemetry is being lost, so
/// a production deployment should surface them (a log line at shutdown, or — carefully — metrics of
/// their own).
///
/// Counters are monotonic for the lifetime of the factory and are never reset.
public struct OCIMetricsStatistics: Sendable, Equatable {
  /// Metric streams the service accepted.
  public var postedStreams: Int
  /// Data points the service accepted.
  public var postedDatapoints: Int
  /// Metric streams the service rejected inside a `200` response.
  ///
  /// Under the service's default non-atomic batching, a partially invalid request still succeeds:
  /// the valid metric objects are ingested and the rejected ones come back in
  /// ``PostMetricDataResponseDetails/failedMetrics``. Rejections are permanent — the metric object
  /// was malformed — so they are counted, logged, and dropped rather than retried.
  public var failedMetrics: Int
  /// Requests that failed outright — transport error, throttling, or a non-`200` status.
  ///
  /// The streams of a failed request go back into the retry buffer and are re-posted on the next
  /// step.
  public var failedRequests: Int
  /// Data points dropped because their timestamp had aged past the service's two-hour window.
  ///
  /// Monitoring accepts timestamps in `(now - 2h, now + 10m)` only, strictly (live-verified), so
  /// data buffered across an outage longer than two hours is permanently unpostable. This counter
  /// is the outage budget being spent.
  public var droppedStaleDatapoints: Int
  /// Metric streams dropped because the retry buffer was full.
  ///
  /// See ``OCIMetricsConfiguration/maximumBufferedStreams``.
  public var droppedBufferedStreams: Int
  /// Observations dropped because a recorder or timer exceeded its per-step distinct-value bound.
  ///
  /// See ``OCIMetricsConfiguration/maximumSamplesPerStream``.
  public var droppedSamples: Int

  /// Creates a statistics tally.
  ///
  /// - Parameters:
  ///   - postedStreams: Metric streams the service accepted.
  ///   - postedDatapoints: Data points the service accepted.
  ///   - failedMetrics: Metric streams the service rejected inside a `200`.
  ///   - failedRequests: Requests that failed outright.
  ///   - droppedStaleDatapoints: Data points dropped for being older than two hours.
  ///   - droppedBufferedStreams: Metric streams dropped because the retry buffer was full.
  ///   - droppedSamples: Observations dropped by a recorder or timer at its per-step bound.
  public init(
    postedStreams: Int = 0,
    postedDatapoints: Int = 0,
    failedMetrics: Int = 0,
    failedRequests: Int = 0,
    droppedStaleDatapoints: Int = 0,
    droppedBufferedStreams: Int = 0,
    droppedSamples: Int = 0
  ) {
    self.postedStreams = postedStreams
    self.postedDatapoints = postedDatapoints
    self.failedMetrics = failedMetrics
    self.failedRequests = failedRequests
    self.droppedStaleDatapoints = droppedStaleDatapoints
    self.droppedBufferedStreams = droppedBufferedStreams
    self.droppedSamples = droppedSamples
  }
}
