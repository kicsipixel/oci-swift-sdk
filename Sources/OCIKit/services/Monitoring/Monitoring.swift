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

/// Client for the OCI Monitoring custom-metric ingestion API.
///
/// Publishes raw metric data points to the Monitoring service, where they can be queried,
/// charted and alarmed on alongside the platform's own `oci_*` metrics. For more information,
/// see [Publishing Custom Metrics](https://docs.oracle.com/en-us/iaas/Content/Monitoring/Tasks/publishingcustommetrics.htm).
///
/// This client covers the ingestion slice of the Monitoring API only — the single operation
/// ``postMetricData(details:opcRequestId:)``. Ingestion is served by a dedicated host,
/// `telemetry-ingestion.{region}.oraclecloud.com`, which differs from the query-side
/// `telemetry.{region}.oraclecloud.com` host; constructing the client with a `region` selects
/// the ingestion host automatically.
///
/// Requests are signed with any OCIKit ``Signer``. The caller's principal needs
/// `allow ... to use metrics in compartment ...`, optionally narrowed with
/// `where target.metrics.namespace='<namespace>'`.
///
/// ## Example Usage
///
/// ```swift
/// let signer = try APIKeySigner(configFilePath: "~/.oci/config")
/// let client = try MonitoringClient(region: .phx, signer: signer)
///
/// let details = PostMetricDataDetails(
///   metricData: [
///     MetricDataDetails(
///       namespace: "my_app",
///       compartmentId: compartmentId,
///       name: "requests",
///       dimensions: ["host": "worker-1"],
///       metadata: ["unit": "count"],
///       datapoints: [MonitoringDatapoint(timestamp: Date(), value: 42)]
///     )
///   ]
/// )
///
/// let response = try await client.postMetricData(details: details)
/// if response.failedMetricsCount > 0 {
///   logger.warning("\(response.failedMetricsCount) metric(s) rejected: \(response.failedMetrics ?? [])")
/// }
/// ```
///
/// - Important: This client is a faithful transport for one request — it does **not** chunk,
///   sanitize, or drop anything on the caller's behalf. Batching a metric stream into
///   service-legal requests is the job of a higher-level backend such as `OCIMetricsFactory`.
///   The per-request limits the caller is responsible for respecting are documented on
///   ``postMetricData(details:opcRequestId:)`` and on the model types.
public struct MonitoringClient: Sendable {
  let endpoint: URL?
  let region: Region?
  let retryConfig: RetryConfig?
  let signer: Signer
  let logger: Logger
  let httpClient: HTTPClient

  // MARK: - Initialization

  /// Initializes the Monitoring metric-ingestion client.
  ///
  /// - Parameters:
  ///   - region: A region used to determine the service endpoint. Resolves to the ingestion host
  ///     `telemetry-ingestion.{region}.oraclecloud.com`, not the query host.
  ///   - endpoint: The fully qualified endpoint URL. If provided, this takes precedence over the region.
  ///   - signer: A signer implementation used for authenticating requests.
  ///   - retryConfig: The retry configuration applied to every operation of this client. `nil` (the default) disables retries.
  ///   - logger: Optional logger for debugging and diagnostics.
  ///   - httpClient: The HTTP transport used to perform requests. Defaults to ``HTTPClient/live``
  ///     (real `URLSession` I/O); tests can inject a recording or replaying transport.
  ///
  /// - Throws: ``MonitoringError/missingRequiredParameter(_:)`` if neither endpoint nor region is specified.
  ///
  /// - Note: Either a region or an endpoint must be specified.
  ///   If an endpoint is specified, it will be used instead of the region.
  public init(
    region: Region? = nil,
    endpoint: String? = nil,
    signer: Signer,
    retryConfig: RetryConfig? = nil,
    logger: Logger = Logger(label: "MonitoringClient"),
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
        throw MonitoringError.missingRequiredParameter("Either endpoint or region must be specified.")
      }
      self.region = region
      let host = Service.monitoringingestion.getHost(in: region)
      self.endpoint = URL(string: "https://\(host)")
    }
  }

  // MARK: - Post Metric Data

  /// Publishes raw metric data points to the Monitoring service.
  ///
  /// The decoded response body is returned rather than discarded, because **partial failures
  /// arrive inside a `200`**: under the default ``MonitoringBatchAtomicity/nonAtomic`` behaviour
  /// the service ingests the valid metric objects and reports the rejected ones in
  /// ``PostMetricDataResponseDetails/failedMetrics``. A caller that only checks for a thrown
  /// error silently loses data. A non-`200` — `400` when *every* metric object failed input
  /// validation, or when a request-level rule was violated — is decoded from the shared
  /// ``DataBody`` error body and thrown as ``MonitoringError/unexpectedStatusCode(_:_:)``.
  ///
  /// The caller is responsible for keeping each request within the service limits; this method
  /// neither chunks nor sanitizes:
  ///
  /// - **≤ 50 unique metric streams** per request (`400` `"The valid range is 1 to 50"`).
  ///   Data points per stream are effectively unbounded.
  /// - **Timestamps within `(now - 2h, now + 10m)`**, strictly enforced. Data points older than
  ///   two hours are permanently unpostable.
  /// - **1–20 dimensions per metric, never empty** (`400` `"dimensions can not be null or
  ///   empty"`). Dimension keys contain no whitespace and are ≤ 256 characters; values are
  ///   non-empty and ≤ 512 characters.
  /// - **Namespace** matches `^[A-Za-z][A-Za-z0-9_]*$` and must not start with `oci_` or
  ///   `oracle_`.
  /// - **50 TPS per tenancy** for this operation.
  ///
  /// - Parameters:
  ///   - details: The metric objects containing the raw metric data points to post.
  ///   - opcRequestId: Unique identifier for the request.
  ///
  /// - Returns: A ``PostMetricDataResponseDetails`` reporting how many metric objects — if any —
  ///   failed input validation, and why.
  ///
  /// - Throws: ``MonitoringError`` if the request could not be built, sent, or decoded, or if the
  ///   service returned a status code other than `200`.
  public func postMetricData(
    details: PostMetricDataDetails,
    opcRequestId: String? = nil
  ) async throws -> PostMetricDataResponseDetails {
    guard let endpoint else {
      throw MonitoringError.missingRequiredParameter("No endpoint has been set")
    }

    let body: Data
    do {
      body = try JSONEncoder().encode(details)
    }
    catch {
      throw MonitoringError.jsonEncodingError("Failed to encode PostMetricDataDetails: \(error)")
    }

    let api = MonitoringAPI.postMetricData(opcRequestId: opcRequestId)
    var req = try buildRequest(api: api, endpoint: endpoint)
    req.httpBody = body

    let (data, response) = try await httpClient.send(req, signer: signer, retry: retryConfig, logger: logger)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw MonitoringError.invalidResponse("Invalid HTTP response")
    }

    if httpResponse.statusCode != 200 {
      let errorBody = try? JSONDecoder().decode(DataBody.self, from: data)
      let message = errorBody?.message ?? String(data: data, encoding: .utf8) ?? ""
      logger.error("[postMetricData] \(errorBody?.code ?? "UnknownError") (\(httpResponse.statusCode)): \(message)")
      throw MonitoringError.unexpectedStatusCode(httpResponse.statusCode, message)
    }

    do {
      let responseDetails = try JSONDecoder().decode(PostMetricDataResponseDetails.self, from: data)
      return responseDetails
    }
    catch {
      throw MonitoringError.jsonDecodingError("Failed to decode response data to PostMetricDataResponseDetails: \(error)")
    }
  }
}
