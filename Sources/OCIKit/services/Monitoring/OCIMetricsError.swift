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

/// Errors raised while configuring the swift-metrics backend, ``OCIMetricsFactory``.
///
/// These are all *configuration* errors, raised eagerly by
/// ``OCIMetricsConfiguration/init(namespace:compartmentId:resourceGroup:commonDimensions:defaultDimensionName:defaultDimensionValue:step:maximumBufferedStreams:maximumSamplesPerStream:)``
/// so a misconfigured process fails at start-up rather than silently posting metrics the service
/// rejects. Everything that can go wrong *after* start-up is non-fatal by design and is counted in
/// ``OCIMetricsStatistics`` instead — a metrics backend must never take an application down.
public enum OCIMetricsError: Error, Sendable, Equatable {
  /// The metric namespace does not satisfy the service's rules.
  ///
  /// A namespace starts with an alphabetical character, contains only alphanumeric characters and
  /// underscores, is at most 256 characters long, and must not use the reserved `oci_` or
  /// `oracle_` prefixes.
  case invalidNamespace(String)

  /// The compartment OCID was empty. Metric data is billed and queried per compartment, so the
  /// service requires one on every metric object.
  case missingCompartmentId

  /// The configured export step was zero or negative.
  ///
  /// Spelled `Swift.Duration` throughout because OCIKit ships as a single module and already
  /// exposes an Object Storage lifecycle model named `Duration`.
  case invalidStep(Swift.Duration)

  /// A buffer bound was zero or negative.
  case invalidBufferBound(String, Int)
}

extension OCIMetricsError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .invalidNamespace(let namespace):
      return
        "Invalid metric namespace \"\(namespace)\": it must match ^[A-Za-z][A-Za-z0-9_]{0,255}$ and must not start with \"oci_\" or \"oracle_\"."
    case .missingCompartmentId:
      return "Missing required parameter: compartmentId must be a non-empty compartment OCID."
    case .invalidStep(let step):
      return "Invalid export step \(step): the step must be greater than zero."
    case .invalidBufferBound(let name, let value):
      return "Invalid buffer bound \(name) = \(value): the bound must be greater than zero."
    }
  }
}
