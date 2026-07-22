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

/// The `TimerHandler` backing a swift-metrics `Timer`.
///
/// A timer is a recorder of durations, so this is a thin façade over an aggregating
/// ``OCIMetricsRecorderHandler`` — same lock-guarded, non-blocking hot path, same per-step
/// collapsing of identical observations into a data point with an occurrence count, same bound on
/// the number of distinct values retained per step.
///
/// Durations are exported **in nanoseconds**, the unit swift-metrics hands them over in. No scaling
/// is applied, because scaling would lose precision on short durations and the service stores raw
/// numbers with no unit of their own; the unit is instead published alongside the metric as
/// ``MetricDataDetails/metadata`` (`["unit": "ns"]`), which is where the Console reads a metric's
/// display unit from.
///
/// `preferDisplayUnit(_:)` is deliberately left at the protocol's no-op default: it is documented as
/// a presentation *hint*, and honouring it would make the same metric arrive in different units
/// depending on which module happened to configure the timer first.
final class OCIMetricsTimerHandler: TimerHandler, OCIMetricsDrainable {
  /// The stream this timer records into.
  let id: OCIMetricsStreamID

  /// The aggregating storage the durations are recorded into.
  private let durations: OCIMetricsRecorderHandler

  /// Creates a timer handler.
  ///
  /// - Parameters:
  ///   - id: The stream this timer records into.
  ///   - maximumSamples: The maximum number of distinct durations retained per step.
  init(id: OCIMetricsStreamID, maximumSamples: Int) {
    self.id = id
    self.durations = OCIMetricsRecorderHandler(id: id, aggregate: true, maximumSamples: maximumSamples)
  }

  // MARK: - TimerHandler

  /// Records a duration. Non-blocking; safe from any task or thread.
  ///
  /// - Parameter duration: The duration in nanoseconds.
  func recordNanoseconds(_ duration: Int64) {
    durations.record(duration)
  }

  // MARK: - OCIMetricsDrainable

  /// Takes the step's durations, in nanoseconds, and starts a new step.
  ///
  /// - Returns: One sample per distinct duration observed during the step, sorted ascending.
  func drain() -> [OCIMetricsStreamSnapshot.Sample] {
    durations.drain()
  }

  /// Takes and clears the tally of distinct durations dropped because the per-step bound was
  /// reached.
  ///
  /// - Returns: The number of distinct durations dropped since the previous call.
  func takeDroppedSamples() -> Int {
    durations.takeDroppedSamples()
  }
}
