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

/// The reason a single metric object failed input validation, together with the metric object
/// itself as the service echoed it back.
///
/// Records of this type arrive inside a **`200`** response — see
/// ``PostMetricDataResponseDetails`` — whenever a non-atomic batch was partially rejected.
public struct FailedMetricRecord: Codable, Sendable {
  /// The error message describing why the metric object failed input validation.
  ///
  /// Example: `The datapoint timestamps must be between 2 hours ago and 10 minutes from now.`
  public let message: String
  /// The metric object that failed, echoed back by the service.
  ///
  /// The echo carries explicit JSON `null`s for the fields that were not supplied
  /// (`count`, `metadata`, `resourceGroup`).
  public let metricData: MetricDataDetails

  /// Creates a failed-metric record.
  ///
  /// - Parameters:
  ///   - message: The reason the metric object failed input validation.
  ///   - metricData: The metric object that failed.
  public init(message: String, metricData: MetricDataDetails) {
    self.message = message
    self.metricData = metricData
  }
}
