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

/// The response body of ``MonitoringClient/postMetricData(details:opcRequestId:)``.
///
/// - Important: A `200` does **not** mean every metric object was ingested. With the default
///   ``MonitoringBatchAtomicity/nonAtomic`` behaviour the service ingests the valid metric
///   objects and reports the rejected ones here, inside the successful response. Callers must
///   inspect ``failedMetricsCount`` — an all-or-nothing read of the HTTP status silently loses
///   data. A `400` is returned only when *every* metric object failed, or when a request-level
///   rule (such as the 50-stream limit) was violated.
public struct PostMetricDataResponseDetails: Codable, Sendable {
  /// The number of metric objects that failed input validation.
  public let failedMetricsCount: Int
  /// A list of the metric objects that failed input validation, and why.
  ///
  /// Absent (or empty) when every metric object in the batch was ingested.
  public let failedMetrics: [FailedMetricRecord]?

  /// Creates a metric-ingestion response body.
  ///
  /// - Parameters:
  ///   - failedMetricsCount: The number of metric objects that failed input validation.
  ///   - failedMetrics: The metric objects that failed, and why.
  public init(failedMetricsCount: Int, failedMetrics: [FailedMetricRecord]? = nil) {
    self.failedMetricsCount = failedMetricsCount
    self.failedMetrics = failedMetrics
  }
}
