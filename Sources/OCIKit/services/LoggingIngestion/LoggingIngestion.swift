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
import Logging

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Client for the OCI Logging Ingestion data plane (`logging-dataplane`, API version `20200831`).
///
/// The service exposes exactly one operation — `PutLogs` — which pushes a batch of
/// log entries into an existing custom log. The log group and the log are
/// control-plane resources: create them with Terraform, the OCI Console, or another
/// SDK, and hand the resulting log OCID to
/// ``putLogs(logId:details:opcRequestId:timestampOpcAgentProcessing:)``.
///
/// Requests are signed like every other OCI request, so all OCIKit signers work
/// (API key, instance principal, resource principal, security token, workload
/// identity). The caller's principal needs the `LOG_CONTENT_PUSH` permission, e.g.
/// `allow dynamic-group my-dg to use log-content in compartment my-compartment`.
///
/// ## Example
/// ```swift
/// let signer = try APIKeySigner(configFilePath: "~/.oci/config")
/// let client = try LoggingIngestClient(region: .phx, signer: signer)
///
/// let details = PutLogsDetails(
///   logEntryBatches: [
///     LogEntryBatch(
///       entries: [LogEntry(data: "hello from Swift")],
///       source: "my-host",
///       type: "com.example.app",
///       defaultlogentrytime: Date()
///     )
///   ]
/// )
/// try await client.putLogs(logId: "ocid1.log.oc1.phx...", details: details)
/// ```
public struct LoggingIngestClient: Sendable {
  let endpoint: URL?
  let region: Region?
  let retryConfig: RetryConfig?
  let signer: Signer
  let logger: Logger
  let httpClient: HTTPClient

  // MARK: - Initialization

  /// Initializes the Logging Ingestion client.
  ///
  /// - Parameters:
  ///   - region: A region used to determine the service endpoint.
  ///   - endpoint: The fully qualified endpoint URL. If provided, this takes precedence over the region.
  ///   - signer: A signer implementation used for authenticating requests.
  ///   - retryConfig: The retry configuration applied to every operation of this client. `nil` (the default) disables retries.
  ///   - logger: Optional logger for debugging and diagnostics.
  ///   - httpClient: The HTTP transport used to perform requests. Defaults to ``HTTPClient/live``
  ///     (real `URLSession` I/O); tests can inject a recording or replaying transport.
  ///
  /// - Throws: ``LoggingIngestionError/missingRequiredParameter(_:)`` if neither endpoint nor region is specified.
  ///
  /// - Note: Either a region or an endpoint must be specified.
  ///   If an endpoint is specified, it will be used instead of the region.
  public init(
    region: Region? = nil,
    endpoint: String? = nil,
    signer: Signer,
    retryConfig: RetryConfig? = nil,
    logger: Logger = Logger(label: "LoggingIngestClient"),
    httpClient: HTTPClient = .live
  ) throws {
    self.signer = signer
    self.retryConfig = retryConfig
    self.logger = logger
    self.httpClient = httpClient

    if let endpoint, let endpointURL = URL(string: endpoint) {
      self.endpoint = endpointURL
      self.region = nil
    }
    else {
      guard let region else {
        throw LoggingIngestionError.missingRequiredParameter("Either endpoint or region must be specified.")
      }
      self.region = region
      let host = Service.loggingingestion.getHost(in: region)
      self.endpoint = URL(string: "https://\(host)")
    }
  }

  // MARK: - Put Logs

  /// Ingests log entries into the log identified by `logId`.
  ///
  /// A successful response means the data has been accepted: the service answers
  /// HTTP 200 with an empty body, so this operation returns no value.
  ///
  /// Limits worth knowing when sizing a call:
  /// - Every ``LogEntry/data`` longer than **10,000 characters** is silently
  ///   truncated to exactly 10,000 characters ending in `...`. Split long messages
  ///   client-side if the full text matters.
  /// - There is **no practical cap on the payload**: requests from 1 MiB up to
  ///   1 GiB are accepted without silent drops. Batch sizing is an ergonomics
  ///   choice (retry amplification, upload latency) rather than a service limit;
  ///   1–10 MiB per flush is a sensible range.
  /// - Timestamps are **not** skew-checked. Entries as old as the log's retention
  ///   window land and index at their claimed time (older ones return HTTP 200 but
  ///   are dropped), and future timestamps are accepted. Logs buffered across an
  ///   outage therefore stay ingestible for days.
  ///
  /// - Parameters:
  ///   - logId: The OCID of the log to ingest into.
  ///   - details: The log batches to emit.
  ///   - opcRequestId: Unique identifier for the request.
  ///   - timestampOpcAgentProcessing: Effective timestamp for when the agent started
  ///     processing the log segment being sent. Encoded as RFC3339 with milliseconds precision.
  ///
  /// - Throws: ``LoggingIngestionError`` if the request could not be built, encoded, or accepted.
  public func putLogs(
    logId: String,
    details: PutLogsDetails,
    opcRequestId: String? = nil,
    timestampOpcAgentProcessing: Date? = nil
  ) async throws {
    guard let endpoint else {
      throw LoggingIngestionError.missingRequiredParameter("No endpoint has been set")
    }

    let api = LoggingIngestionAPI.putLogs(
      logId: logId,
      opcRequestId: opcRequestId,
      timestampOpcAgentProcessing: timestampOpcAgentProcessing
    )

    // `buildRequest` sets `Content-Type: application/json` before the request is
    // handed to the signer — body-bearing verbs sign `content-length`,
    // `content-type`, and `x-content-sha256`, so the header must be in place first.
    var req = try buildRequest(api: api, endpoint: endpoint)

    do {
      req.httpBody = try JSONEncoder().encode(details)
    }
    catch {
      throw LoggingIngestionError.jsonEncodingError("Failed to encode PutLogsDetails in putLogs: \(error)")
    }

    let (data, response) = try await httpClient.send(req, signer: signer, retry: retryConfig, logger: logger)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw LoggingIngestionError.invalidResponse("Invalid HTTP response")
    }

    guard (200..<300).contains(httpResponse.statusCode) else {
      let errorBody = try? JSONDecoder().decode(DataBody.self, from: data)
      let message = errorBody?.message ?? String(data: data, encoding: .utf8) ?? ""
      logger.error("[putLogs] \(errorBody?.code ?? "Unknown") (\(httpResponse.statusCode)): \(message)")
      throw LoggingIngestionError.unexpectedStatusCode(httpResponse.statusCode, message)
    }
  }
}
