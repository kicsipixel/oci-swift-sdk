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

/// The request body of
/// ``MonitoringClient/postMetricData(details:opcRequestId:)`` — an array of metric objects
/// containing the raw metric data points to publish.
public struct PostMetricDataDetails: Codable, Sendable {
  /// The metric objects to post, one per metric stream.
  ///
  /// - Important: At most **50 unique metric streams** per request. A larger array is rejected
  ///   with `400` `"The valid range is 1 to 50"` (live-verified). ``MonitoringClient`` does not
  ///   chunk on the caller's behalf.
  public let metricData: [MetricDataDetails]
  /// How to treat a batch in which some metric objects fail input validation.
  ///
  /// Omitted from the encoded body when `nil`, in which case the service applies its default,
  /// ``MonitoringBatchAtomicity/nonAtomic``.
  public let batchAtomicity: MonitoringBatchAtomicity?

  /// Creates a metric-ingestion request body.
  ///
  /// - Parameters:
  ///   - metricData: The metric objects to post. At most 50 unique metric streams.
  ///   - batchAtomicity: The partial-failure behaviour. Defaults to `nil`, i.e. the service
  ///     default of ``MonitoringBatchAtomicity/nonAtomic``.
  public init(metricData: [MetricDataDetails], batchAtomicity: MonitoringBatchAtomicity? = nil) {
    self.metricData = metricData
    self.batchAtomicity = batchAtomicity
  }
}
