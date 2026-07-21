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
//
// Hermetic tests for MonitoringClient — no ~/.oci/config, no credentials, no
// network. Two shapes are used, mirroring SecretsHermeticTests.swift:
//   • replay a committed fixture (captured live via `oci raw-request` against
//     telemetry-ingestion, then sanitized) and assert on the decoded model —
//     locks response parsing for both the clean and partial-failure shapes.
//   • inject a recording HTTPClient closure and assert on the request the
//     client built (host, method, path, body) — locks request building.
// Both run anywhere (CI, fork PRs, offline).
//

import Foundation
import Testing

@testable import OCIKit

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

// A no-op-ish signer. These tests exercise request building and response
// parsing, not signature correctness. It stamps an Authorization header so a
// request-shape test can confirm the signing path was reached.
private struct StubSigner: Signer {
  func sign(_ req: inout URLRequest) throws {
    req.setValue(#"Signature version="1""#, forHTTPHeaderField: "Authorization")
  }
}

// Sendable-safe capture of the last request the client handed to the transport.
private actor RequestRecorder {
  private(set) var last: URLRequest?
  func record(_ request: URLRequest) { last = request }
}

struct MonitoringHermeticTests {
  private static let compartmentId = "ocid1.compartment.oc1..EXAMPLE"

  // Fixtures live next to this test file; resolve via #filePath so no SwiftPM
  // resource bundling is needed (the source tree is present at test time).
  private func fixtureURL(_ name: String) -> URL {
    URL(filePath: #filePath).deletingLastPathComponent().appending(path: "Fixtures/\(name)")
  }

  private func replayClient(_ fixture: String) throws -> MonitoringClient {
    let http = try HTTPClient.replaying(fromFile: fixtureURL(fixture))
    return try MonitoringClient(region: .phx, signer: StubSigner(), httpClient: http)
  }

  // Builds a client whose transport records the request and returns a canned response.
  private func recordingClient(
    status: Int = 200,
    body: Data,
    recorder: RequestRecorder
  ) throws -> MonitoringClient {
    let http = HTTPClient { request in
      await recorder.record(request)
      let response = HTTPURLResponse(
        url: request.url!,
        statusCode: status,
        httpVersion: "HTTP/1.1",
        headerFields: [:]
      )!
      return (body, response)
    }
    return try MonitoringClient(region: .phx, signer: StubSigner(), httpClient: http)
  }

  private func oneMetric() -> PostMetricDataDetails {
    PostMetricDataDetails(
      metricData: [
        MetricDataDetails(
          namespace: "ocikit_probe",
          compartmentId: Self.compartmentId,
          name: "requests",
          dimensions: ["host": "worker-1"],
          datapoints: [MonitoringDatapoint(timestamp: Date(timeIntervalSince1970: 0), value: 1)]
        )
      ]
    )
  }

  // MARK: - Response decoding (replay captured wire fixtures)

  @Test("postMetricData: a clean 200 decodes to failedMetricsCount == 0")
  func decodesCleanResponse() async throws {
    let client = try replayClient("postMetricData_200_clean.json")

    let response = try await client.postMetricData(details: oneMetric())

    #expect(response.failedMetricsCount == 0)
    #expect(response.failedMetrics?.isEmpty == true)
  }

  @Test("postMetricData: a 200 with failedMetrics is returned, not thrown — partial-failure pass-through")
  func decodesPartialFailureResponse() async throws {
    let client = try replayClient("postMetricData_200_partialFailure.json")

    // No error is thrown even though a metric object was rejected: partial
    // failure inside a 200 is reported in the body, not via an Error.
    let response = try await client.postMetricData(details: oneMetric())

    #expect(response.failedMetricsCount == 1)
    let failed = try #require(response.failedMetrics?.first)
    #expect(failed.message.contains("2 hours ago"))
    #expect(failed.metricData.namespace == "ocikit_probe")
    #expect(failed.metricData.name == "probe_bad")
    // Echoed nulls decode cleanly.
    #expect(failed.metricData.metadata == nil)
    #expect(failed.metricData.resourceGroup == nil)
  }

  @Test("postMetricData: a 400 all-failed response throws MonitoringError.unexpectedStatusCode with the DataBody message")
  func allFailedResponseThrows() async throws {
    let client = try replayClient("postMetricData_400_allFailed.json")

    do {
      _ = try await client.postMetricData(details: oneMetric())
      Issue.record("expected postMetricData to throw for a 400 response")
    }
    catch MonitoringError.unexpectedStatusCode(let code, let message) {
      #expect(code == 400)
      #expect(message.contains("dimensions can not be null or empty"))
    }
    catch {
      Issue.record("expected MonitoringError.unexpectedStatusCode, got \(error)")
    }
  }

  // MARK: - Request shape (record the outgoing request)

  @Test("postMetricData: POSTs to the telemetry-ingestion host at /20180401/metrics")
  func requestShapeHostAndPath() async throws {
    let recorder = RequestRecorder()
    let body = Data(#"{"failedMetricsCount":0}"#.utf8)
    let client = try recordingClient(body: body, recorder: recorder)

    _ = try await client.postMetricData(details: oneMetric(), opcRequestId: "req-abc")

    let req = await recorder.last
    #expect(req?.httpMethod == "POST")
    #expect(req?.url?.host == "telemetry-ingestion.us-phoenix-1.oraclecloud.com")
    #expect(req?.url?.path == "/20180401/metrics")
    #expect(req?.value(forHTTPHeaderField: "opc-request-id") == "req-abc")
    #expect(req?.value(forHTTPHeaderField: "Authorization") != nil)  // signer ran
  }

  @Test("postMetricData: request body carries the dimension map and an RFC3339-ms timestamp")
  func requestBodyEncoding() async throws {
    let recorder = RequestRecorder()
    let body = Data(#"{"failedMetricsCount":0}"#.utf8)
    let client = try recordingClient(body: body, recorder: recorder)

    let details = PostMetricDataDetails(
      metricData: [
        MetricDataDetails(
          namespace: "ocikit_probe",
          compartmentId: Self.compartmentId,
          name: "latency_ms",
          dimensions: ["region": "phx", "host": "worker-1"],
          datapoints: [MonitoringDatapoint(timestamp: Date(timeIntervalSince1970: 1_675_213_349.6), value: 12.5)]
        )
      ]
    )
    _ = try await client.postMetricData(details: details)

    let req = await recorder.last
    let sentBody = try #require(req?.httpBody)
    let json = try #require(try JSONSerialization.jsonObject(with: sentBody) as? [String: Any])
    // No batchAtomicity was supplied — omitted from the wire body, not encoded as null.
    #expect(json["batchAtomicity"] == nil)
    let metricData = try #require(json["metricData"] as? [[String: Any]])
    let metric = try #require(metricData.first)
    #expect(metric["namespace"] as? String == "ocikit_probe")
    let dimensions = try #require(metric["dimensions"] as? [String: String])
    #expect(dimensions == ["region": "phx", "host": "worker-1"])
    let datapoints = try #require(metric["datapoints"] as? [[String: Any]])
    #expect(datapoints.first?["timestamp"] as? String == "2023-02-01T01:02:29.600Z")
    #expect(datapoints.first?["value"] as? Double == 12.5)
  }
}
