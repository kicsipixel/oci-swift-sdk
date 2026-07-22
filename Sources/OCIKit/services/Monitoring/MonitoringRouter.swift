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

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// API routes for the OCI Monitoring metric-ingestion service (API version `20180401`).
///
/// Only the ingestion slice of the Monitoring API is routed here. Ingestion is served by a
/// dedicated host — `telemetry-ingestion.{region}.oraclecloud.com` — that differs from the
/// query-side `telemetry.{region}.oraclecloud.com` host used by `SummarizeMetricsData` and
/// `ListMetrics`. See the
/// [Monitoring documentation](https://docs.oracle.com/en-us/iaas/Content/Monitoring/home.htm).
public enum MonitoringAPI: API {
  /// The service API version path segment shared by every route.
  static let version = "/20180401"

  // MARK: Metric ingestion

  /// Publishes raw metric data points to the Monitoring service.
  case postMetricData(opcRequestId: String? = nil)

  // MARK: - Path

  public var path: String {
    let v = Self.version
    switch self {
    case .postMetricData:
      return "\(v)/metrics"
    }
  }

  // MARK: - HTTP Method

  public var method: HTTPMethod {
    switch self {
    case .postMetricData:
      return .post
    }
  }

  // MARK: - Query Items

  public var queryItems: [URLQueryItem]? {
    switch self {
    case .postMetricData:
      return nil
    }
  }

  // MARK: - Headers

  public var headers: [String: String]? {
    var headers: [String: String] = [:]
    switch self {
    case .postMetricData(let opcRequestId):
      if let opcRequestId { headers["opc-request-id"] = opcRequestId }
    }
    return headers.isEmpty ? nil : headers
  }
}
