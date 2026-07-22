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

/// API routes for the OCI Logging Ingestion data plane (`logging-dataplane`, API version `20200831`).
///
/// This router only covers `PutLogs`, the single data-plane operation of the
/// service. Log groups and logs themselves are control-plane resources and are
/// intentionally out of scope — create them with Terraform, the OCI Console, or
/// another SDK, and pass the resulting log OCID here. See the
/// [Logging Ingestion API](https://docs.oracle.com/en-us/iaas/api/#/en/logging-dataplane/20200831/LogEntry/PutLogs).
public enum LoggingIngestionAPI: API {
  /// The service API version path segment shared by every route.
  static let version = "/20200831"

  /// Ingests a batch of log entries into the log identified by `logId`.
  ///
  /// - Parameters:
  ///   - logId: The OCID of the log to ingest into.
  ///   - opcRequestId: Optional client-supplied request id for tracing.
  ///   - timestampOpcAgentProcessing: Optional effective timestamp for when the
  ///     agent started processing the log segment being sent. Encoded as RFC3339
  ///     with milliseconds precision.
  case putLogs(
    logId: String,
    opcRequestId: String? = nil,
    timestampOpcAgentProcessing: Date? = nil
  )

  // MARK: - Path

  public var path: String {
    switch self {
    case .putLogs(let logId, _, _):
      return "\(Self.version)/logs/\(logId)/actions/push"
    }
  }

  // MARK: - HTTP Method

  public var method: HTTPMethod {
    switch self {
    case .putLogs:
      return .post
    }
  }

  // MARK: - Query Items

  public var queryItems: [URLQueryItem]? { nil }

  // MARK: - Headers

  public var headers: [String: String]? {
    switch self {
    case .putLogs(_, let opcRequestId, let timestampOpcAgentProcessing):
      var headers: [String: String] = [:]
      if let opcRequestId { headers["opc-request-id"] = opcRequestId }
      if let timestampOpcAgentProcessing {
        headers["timestamp-opc-agent-processing"] = timestampOpcAgentProcessing.toRFC3339()
      }
      return headers.isEmpty ? nil : headers
    }
  }
}
