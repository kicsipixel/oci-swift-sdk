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

/// One export step's worth of values, drained from a single metric handler.
///
/// A snapshot is the hand-off between the lock-guarded hot path (the handlers) and the exporter
/// actor: the handler produces it synchronously under its own `Mutex` and then owns nothing the
/// exporter touches. ``OCIMetricsConfiguration/metricData(for:at:)`` turns it into the wire model,
/// ``MetricDataDetails``.
struct OCIMetricsStreamSnapshot: Sendable {
  /// One metric value together with how many times it was observed during the step.
  ///
  /// Identical observations are collapsed into a single sample rather than repeated, because the
  /// service's ``MonitoringDatapoint/count`` field expresses exactly that: *n* occurrences of
  /// `value`. Collapsing keeps a busy timer's step from turning into thousands of identical
  /// data points on the wire while preserving the statistics the service computes from them.
  struct Sample: Sendable, Equatable {
    /// The observed value.
    let value: Double
    /// How many times ``value`` was observed during the step. Always at least `1`.
    let count: Int

    /// Creates a sample.
    ///
    /// - Parameters:
    ///   - value: The observed value.
    ///   - count: How many times the value was observed. Defaults to `1`.
    init(value: Double, count: Int = 1) {
      self.value = value
      self.count = count
    }
  }

  /// Which stream the samples belong to.
  let id: OCIMetricsStreamID
  /// The values observed during the step. Never empty — a handler with nothing to report is
  /// skipped rather than snapshotted.
  let samples: [Sample]

  /// Creates a snapshot.
  ///
  /// - Parameters:
  ///   - id: The stream the samples belong to.
  ///   - samples: The values observed during the step.
  init(id: OCIMetricsStreamID, samples: [Sample]) {
    self.id = id
    self.samples = samples
  }
}
