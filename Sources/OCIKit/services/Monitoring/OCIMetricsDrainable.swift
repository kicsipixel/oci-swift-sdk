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

/// The registry's view of a metric handler: something identified by a stream id whose accumulated
/// values can be taken away once per export step.
///
/// swift-metrics' `CounterHandler` / `RecorderHandler` / `TimerHandler` protocols only describe the
/// *recording* side. This adds the *draining* side, so ``OCIMetricsRegistry`` can hold the three
/// concrete handler types in one dictionary and snapshot them uniformly.
///
/// Conformers are reference types (a swift-metrics handler must be a class so `destroy()` can
/// identify it) and `Sendable` (the hot path is called from arbitrary tasks and threads).
protocol OCIMetricsDrainable: AnyObject, Sendable {
  /// The stream this handler records into.
  var id: OCIMetricsStreamID { get }

  /// Takes the values accumulated since the previous drain and resets the step state.
  ///
  /// Called once per export step by ``OCIMetricsRegistry/drain()``, and once more when the handler
  /// is destroyed so the final step's values are not silently lost.
  ///
  /// - Returns: The step's samples, or an empty array when the handler has nothing to report.
  ///   An empty result costs the stream nothing: no metric object is built and no slot is spent
  ///   against the 50-stream-per-request limit.
  func drain() -> [OCIMetricsStreamSnapshot.Sample]

  /// Takes and clears the number of observations this handler had to drop to stay within its
  /// per-step sample bound.
  ///
  /// - Returns: The number of observations dropped since the previous call. Handlers with a
  ///   fixed-size step state — counters and gauges — never drop and use the default of `0`.
  func takeDroppedSamples() -> Int
}

extension OCIMetricsDrainable {
  /// Handlers whose step state is a single value can never overflow a sample bound.
  func takeDroppedSamples() -> Int { 0 }
}
