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

/// The `CounterHandler` backing a swift-metrics `Counter`.
///
/// Counters are exported as a **per-step delta**: each step reports how much the counter advanced
/// since the previous export, not its lifetime total. That is what a step-based backend must do —
/// the service aggregates the posted data points itself, so a cumulative value would be summed
/// again on every step and the resulting chart would grow quadratically.
///
/// Increments are recorded synchronously under a `Mutex` (`Synchronization`), so the hot path never
/// allocates a task, never blocks on a lock held across an `await`, and stays `Sendable`-clean
/// under strict concurrency.
///
/// A step in which the counter was never incremented reports nothing at all, rather than a `0`.
/// Idle streams therefore cost neither a request slot nor a data point, and OCI's alarm evaluation
/// treats the resulting gap as "no data" rather than "zero".
final class OCIMetricsCounterHandler: CounterHandler, OCIMetricsDrainable {
  /// The stream this counter records into.
  let id: OCIMetricsStreamID

  /// The per-step accumulator, guarded by ``state``.
  private struct State {
    /// The sum of the increments observed since the last drain.
    var delta: Int64 = 0
    /// How many `increment(by:)` calls have landed since the last drain. Used only to tell an
    /// untouched step (report nothing) from a step incremented by zero (report `0`).
    var increments: Int = 0
  }

  private let state = Mutex(State())

  /// Creates a counter handler.
  ///
  /// - Parameter id: The stream this counter records into.
  init(id: OCIMetricsStreamID) {
    self.id = id
  }

  // MARK: - CounterHandler

  /// Advances the counter. Non-blocking; safe from any task or thread.
  ///
  /// - Parameter amount: How much to advance by. Overflow wraps rather than traps — a metrics
  ///   backend must never crash the application it is instrumenting.
  func increment(by amount: Int64) {
    state.withLock { state in
      state.delta &+= amount
      state.increments += 1
    }
  }

  /// Resets the counter, discarding the delta accumulated so far in the current step.
  ///
  /// Only the pending step is affected; data points already posted for earlier steps are, of
  /// course, untouched.
  func reset() {
    state.withLock { $0 = State() }
  }

  // MARK: - OCIMetricsDrainable

  /// Takes the step's delta and starts a new step.
  ///
  /// - Returns: A single sample carrying the delta, or an empty array if the counter was not
  ///   incremented during the step. ``OCIMetricsStreamSnapshot/Sample/count`` is `1`: the delta is
  ///   *one* observation of the step's total, and reporting the number of `increment(by:)` calls
  ///   instead would multiply the value in every `sum()` and `mean()` the service computes.
  func drain() -> [OCIMetricsStreamSnapshot.Sample] {
    let snapshot = state.withLock { state -> State in
      let snapshot = state
      state = State()
      return snapshot
    }
    guard snapshot.increments > 0 else { return [] }
    return [OCIMetricsStreamSnapshot.Sample(value: Double(snapshot.delta))]
  }
}
