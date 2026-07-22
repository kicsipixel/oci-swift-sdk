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
import Synchronization

/// The `RecorderHandler` backing a swift-metrics `Recorder` and `Gauge`.
///
/// swift-metrics distinguishes the two by the `aggregate` flag `makeRecorder` is called with, and
/// the two export very differently:
///
/// - **`aggregate == true`** (a `Recorder`) keeps every value observed during the step. Identical
///   values collapse into one sample carrying an occurrence count, which is exactly what the
///   service's ``MonitoringDatapoint/count`` field means — the posted statistics are unchanged and
///   a repetitive stream stays small on the wire.
/// - **`aggregate == false`** (a `Gauge`) keeps only the most recent value, and keeps reporting it
///   every step until it is set again. A gauge describes a level, not an event, so a step in which
///   nobody called `record` is not a gap — the level simply did not change.
///
/// Values are recorded synchronously under a `Mutex` (`Synchronization`): non-blocking,
/// allocation-light, and `Sendable`-clean under strict concurrency.
///
/// The number of *distinct* values retained per step is bounded by `maximumSamples`. Once the bound
/// is reached, repeats of an already-seen value still count, but new distinct values are dropped
/// and tallied — a high-cardinality recorder (nanosecond latencies, say) degrades into a truncated
/// histogram instead of growing the process's memory without limit.
final class OCIMetricsRecorderHandler: RecorderHandler, OCIMetricsDrainable {
  /// The stream this recorder records into.
  let id: OCIMetricsStreamID
  /// Whether every value of the step is kept (`Recorder`) or only the last one (`Gauge`).
  let aggregate: Bool
  /// The maximum number of distinct values retained per step.
  let maximumSamples: Int

  /// The per-step accumulator, guarded by ``state``.
  private struct State {
    /// Occurrence count per distinct value, for the aggregating case.
    var occurrences: [Double: Int] = [:]
    /// The most recent value, for the gauge case. Deliberately survives a drain.
    var last: Double?
    /// Distinct values dropped because ``maximumSamples`` was reached, plus observations dropped
    /// for not being finite.
    var dropped: Int = 0
  }

  private let state = Mutex(State())

  /// Creates a recorder handler.
  ///
  /// - Parameters:
  ///   - id: The stream this recorder records into.
  ///   - aggregate: `true` for a `Recorder`, `false` for a `Gauge`.
  ///   - maximumSamples: The maximum number of distinct values retained per step.
  init(id: OCIMetricsStreamID, aggregate: Bool, maximumSamples: Int) {
    self.id = id
    self.aggregate = aggregate
    self.maximumSamples = maximumSamples
  }

  // MARK: - RecorderHandler

  /// Records an integer value. Non-blocking; safe from any task or thread.
  ///
  /// - Parameter value: The value to record.
  func record(_ value: Int64) {
    record(Double(value))
  }

  /// Records a floating-point value. Non-blocking; safe from any task or thread.
  ///
  /// `NaN` and `±Infinity` are dropped and counted in
  /// ``OCIMetricsStatistics/droppedSamples``: JSON has no representation for them, so `JSONEncoder`
  /// refuses the request body they would appear in — which would fail the whole 50-stream chunk
  /// carrying them, not just this metric. A gauge would then repeat the poison value on every step
  /// for the life of the process (`gauge.record(Double(errors) / Double(total))` with `total == 0`
  /// is the canonical way to get one), and an aggregating recorder would spend its whole
  /// distinct-value budget on it, since `NaN` never compares equal to itself.
  ///
  /// - Parameter value: The value to record.
  func record(_ value: Double) {
    guard value.isFinite else {
      state.withLock { $0.dropped += 1 }
      return
    }
    state.withLock { state in
      state.last = value
      guard aggregate else { return }
      if state.occurrences[value] != nil {
        state.occurrences[value, default: 0] += 1
      }
      else if state.occurrences.count < maximumSamples {
        state.occurrences[value] = 1
      }
      else {
        state.dropped += 1
      }
    }
  }

  // MARK: - OCIMetricsDrainable

  /// Takes the step's values and starts a new step.
  ///
  /// - Returns: For a `Recorder`, one sample per distinct value observed during the step, sorted
  ///   ascending so the request body is deterministic. For a `Gauge`, a single sample carrying the
  ///   last value set — repeated every step until it changes. Empty when nothing has ever been
  ///   recorded.
  func drain() -> [OCIMetricsStreamSnapshot.Sample] {
    state.withLock { state in
      guard aggregate else {
        guard let last = state.last else { return [] }
        return [OCIMetricsStreamSnapshot.Sample(value: last)]
      }
      let samples =
        state.occurrences
        .sorted { $0.key < $1.key }
        .map { OCIMetricsStreamSnapshot.Sample(value: $0.key, count: $0.value) }
      state.occurrences.removeAll(keepingCapacity: true)
      return samples
    }
  }

  /// Takes and clears the tally of observations dropped — because ``maximumSamples`` was reached,
  /// or because the value was not finite.
  ///
  /// - Returns: The number of observations dropped since the previous call.
  func takeDroppedSamples() -> Int {
    state.withLock { state in
      let dropped = state.dropped
      state.dropped = 0
      return dropped
    }
  }
}
