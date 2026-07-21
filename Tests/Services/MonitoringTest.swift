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
// Credential-free unit tests for MonitoringClient (#90): router path/method,
// request encoding, response decoding, enum raw values, and error mapping.
// Hermetic wire-level tests (full request/response round-trips through the
// client, via a fixture replay or a recording transport) live in
// MonitoringHermeticTests.swift.
//

import Foundation
import Testing

@testable import OCIKit

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

// MARK: - Router

struct MonitoringRouterTests {
  @Test("postMetricData routes to POST /20180401/metrics")
  func postMetricDataPath() {
    let api = MonitoringAPI.postMetricData()
    #expect(api.path == "/20180401/metrics")
    #expect(api.method == .post)
    #expect(api.queryItems == nil)
  }

  @Test("postMetricData omits the opc-request-id header when not supplied")
  func postMetricDataHeadersOmittedWhenNil() {
    #expect(MonitoringAPI.postMetricData().headers == nil)
  }

  @Test("postMetricData carries opc-request-id when supplied")
  func postMetricDataHeadersPresent() {
    let headers = MonitoringAPI.postMetricData(opcRequestId: "req-1").headers ?? [:]
    #expect(headers["opc-request-id"] == "req-1")
  }
}

// MARK: - Enums

struct MonitoringEnumsTests {
  @Test("MonitoringBatchAtomicity raw values match the OCI wire strings")
  func batchAtomicityRawValues() {
    #expect(MonitoringBatchAtomicity.atomic.rawValue == "ATOMIC")
    #expect(MonitoringBatchAtomicity.nonAtomic.rawValue == "NON_ATOMIC")
  }
}

// MARK: - Model encoding (request wire format)

struct MonitoringModelEncodingTests {
  /// Encodes a value and returns the resulting JSON as a dictionary for inspection.
  private func jsonObject<T: Encodable>(_ value: T) throws -> [String: Any] {
    let data = try JSONEncoder().encode(value)
    return try JSONSerialization.jsonObject(with: data) as! [String: Any]
  }

  @Test("MonitoringDatapoint encodes the timestamp as RFC3339 with millisecond precision")
  func datapointEncodesRFC3339Timestamp() throws {
    // 2023-02-01T01:02:29.600Z, expressed without relying on a particular TimeZone default.
    let timestamp = Date(timeIntervalSince1970: 1_675_213_349.6)
    let point = MonitoringDatapoint(timestamp: timestamp, value: 42.5, count: 3)

    let json = try jsonObject(point)
    let encoded = try #require(json["timestamp"] as? String)
    #expect(encoded == "2023-02-01T01:02:29.600Z")
    #expect(json["value"] as? Double == 42.5)
    #expect(json["count"] as? Int == 3)
  }

  @Test("MonitoringDatapoint omits count from the encoded body when nil")
  func datapointOmitsNilCount() throws {
    let point = MonitoringDatapoint(timestamp: Date(timeIntervalSince1970: 0), value: 1)
    let json = try jsonObject(point)
    #expect(json["count"] == nil)
  }

  @Test("MetricDataDetails encodes the dimensions map and omits nil metadata/resourceGroup")
  func metricDataDetailsEncodesDimensions() throws {
    let details = MetricDataDetails(
      namespace: "ocikit_probe",
      compartmentId: "ocid1.compartment.oc1..EXAMPLE",
      name: "requests",
      dimensions: ["host": "worker-1", "region": "phx"],
      datapoints: [MonitoringDatapoint(timestamp: Date(timeIntervalSince1970: 0), value: 1)]
    )

    let json = try jsonObject(details)
    let dimensions = try #require(json["dimensions"] as? [String: String])
    #expect(dimensions == ["host": "worker-1", "region": "phx"])
    #expect(json["namespace"] as? String == "ocikit_probe")
    #expect(json["compartmentId"] as? String == "ocid1.compartment.oc1..EXAMPLE")
    #expect(json["name"] as? String == "requests")
    // Not supplied at init — omitted, not encoded as null.
    #expect(json["metadata"] == nil)
    #expect(json["resourceGroup"] == nil)
  }

  @Test("MetricDataDetails encodes metadata and resourceGroup when supplied")
  func metricDataDetailsEncodesOptionalFieldsWhenPresent() throws {
    let details = MetricDataDetails(
      namespace: "ocikit_probe",
      resourceGroup: "probe-group",
      compartmentId: "ocid1.compartment.oc1..EXAMPLE",
      name: "requests",
      dimensions: ["host": "worker-1"],
      metadata: ["unit": "count"],
      datapoints: [MonitoringDatapoint(timestamp: Date(timeIntervalSince1970: 0), value: 1)]
    )

    let json = try jsonObject(details)
    #expect(json["resourceGroup"] as? String == "probe-group")
    let metadata = try #require(json["metadata"] as? [String: String])
    #expect(metadata == ["unit": "count"])
  }

  @Test("PostMetricDataDetails omits batchAtomicity from the encoded body when nil")
  func postMetricDataDetailsOmitsNilBatchAtomicity() throws {
    let details = PostMetricDataDetails(
      metricData: [
        MetricDataDetails(
          namespace: "ocikit_probe",
          compartmentId: "ocid1.compartment.oc1..EXAMPLE",
          name: "requests",
          dimensions: ["host": "worker-1"],
          datapoints: [MonitoringDatapoint(timestamp: Date(timeIntervalSince1970: 0), value: 1)]
        )
      ]
    )

    let json = try jsonObject(details)
    #expect(json["batchAtomicity"] == nil)
    let metricData = try #require(json["metricData"] as? [[String: Any]])
    #expect(metricData.count == 1)
  }

  @Test("PostMetricDataDetails encodes batchAtomicity when supplied")
  func postMetricDataDetailsEncodesBatchAtomicityWhenPresent() throws {
    let details = PostMetricDataDetails(
      metricData: [
        MetricDataDetails(
          namespace: "ocikit_probe",
          compartmentId: "ocid1.compartment.oc1..EXAMPLE",
          name: "requests",
          dimensions: ["host": "worker-1"],
          datapoints: [MonitoringDatapoint(timestamp: Date(timeIntervalSince1970: 0), value: 1)]
        )
      ],
      batchAtomicity: .atomic
    )

    let json = try jsonObject(details)
    #expect(json["batchAtomicity"] as? String == "ATOMIC")
  }
}

// MARK: - Model decoding (response wire format)

struct MonitoringModelDecodingTests {
  @Test("PostMetricDataResponseDetails decodes a clean response with an empty failedMetrics array")
  func decodesCleanResponse() throws {
    let json = """
      {"failedMetricsCount":0,"failedMetrics":[]}
      """
    let response = try JSONDecoder().decode(PostMetricDataResponseDetails.self, from: Data(json.utf8))
    #expect(response.failedMetricsCount == 0)
    #expect(response.failedMetrics?.isEmpty == true)
  }

  @Test("PostMetricDataResponseDetails decodes a clean response with failedMetrics entirely absent")
  func decodesCleanResponseWithMissingFailedMetrics() throws {
    let json = #"{"failedMetricsCount":0}"#
    let response = try JSONDecoder().decode(PostMetricDataResponseDetails.self, from: Data(json.utf8))
    #expect(response.failedMetricsCount == 0)
    #expect(response.failedMetrics == nil)
  }

  @Test("PostMetricDataResponseDetails decodes the live-verified partial-failure shape, tolerating null metricData fields")
  func decodesPartialFailureResponse() throws {
    // Verbatim wire shape captured live against telemetry-ingestion (BRIEF.md), with the
    // real compartment OCID swapped for a sanitized placeholder. The echoed metricData
    // carries explicit JSON nulls for count/metadata/resourceGroup.
    let json = """
      {
        "failedMetricsCount": 1,
        "failedMetrics": [
          {
            "message": "The datapoint timestamps must be between 2 hours ago and 10 minutes from now.",
            "metricData": {
              "compartmentId": "ocid1.compartment.oc1..EXAMPLE",
              "datapoints": [{"count": null, "timestamp": "2020-01-01T00:00:00.000Z", "value": 2.0}],
              "dimensions": {"source": "cli-probe"},
              "metadata": null,
              "name": "probe_bad",
              "namespace": "ocikit_probe",
              "resourceGroup": null
            }
          }
        ]
      }
      """
    let response = try JSONDecoder().decode(PostMetricDataResponseDetails.self, from: Data(json.utf8))
    #expect(response.failedMetricsCount == 1)
    let failed = try #require(response.failedMetrics?.first)
    #expect(failed.message == "The datapoint timestamps must be between 2 hours ago and 10 minutes from now.")
    #expect(failed.metricData.compartmentId == "ocid1.compartment.oc1..EXAMPLE")
    #expect(failed.metricData.namespace == "ocikit_probe")
    #expect(failed.metricData.name == "probe_bad")
    #expect(failed.metricData.dimensions == ["source": "cli-probe"])
    // Explicit JSON nulls decode to nil, not a thrown error.
    #expect(failed.metricData.metadata == nil)
    #expect(failed.metricData.resourceGroup == nil)
    #expect(failed.metricData.datapoints.first?.count == nil)
    #expect(failed.metricData.datapoints.first?.value == 2.0)
    #expect(failed.metricData.datapoints.first?.timestamp == Date.fromRFC3339("2020-01-01T00:00:00.000Z"))
  }

  @Test("MonitoringDatapoint tolerates a timestamp without a fractional-seconds component")
  func datapointDecodesNonFractionalTimestamp() throws {
    let json = #"{"timestamp":"2023-02-01T01:02:29Z","value":1.0}"#
    let point = try JSONDecoder().decode(MonitoringDatapoint.self, from: Data(json.utf8))
    #expect(point.value == 1.0)

    let plain = ISO8601DateFormatter()
    plain.formatOptions = [.withInternetDateTime]
    let expected = try #require(plain.date(from: "2023-02-01T01:02:29Z"))
    #expect(point.timestamp == expected)
  }
}

// MARK: - Errors

struct MonitoringErrorTests {
  @Test("MonitoringError descriptions carry the underlying detail")
  func errorDescriptions() {
    let invalidResponse = MonitoringError.invalidResponse("Bad response")
    #expect(invalidResponse.localizedDescription.contains("Bad response"))

    let invalidURL = MonitoringError.invalidURL("https://bad.url")
    #expect(invalidURL.localizedDescription.contains("https://bad.url"))

    let jsonDecoding = MonitoringError.jsonDecodingError("Missing field")
    #expect(jsonDecoding.localizedDescription.contains("Missing field"))

    let jsonEncoding = MonitoringError.jsonEncodingError("Bad payload")
    #expect(jsonEncoding.localizedDescription.contains("Bad payload"))

    let missingParam = MonitoringError.missingRequiredParameter("region")
    #expect(missingParam.localizedDescription.contains("region"))

    let unexpectedStatus = MonitoringError.unexpectedStatusCode(400, "dimensions can not be null or empty")
    #expect(unexpectedStatus.localizedDescription.contains("400"))
    #expect(unexpectedStatus.localizedDescription.contains("dimensions can not be null or empty"))
  }
}

// MARK: - Client initialization

struct MonitoringClientInitTests {
  private struct NoopSigner: Signer {
    func sign(_ req: inout URLRequest) throws {}
  }

  @Test("Initializing with a region resolves the telemetry-ingestion host")
  func initWithRegionResolvesIngestionHost() throws {
    let client = try MonitoringClient(region: .phx, signer: NoopSigner())
    #expect(client.endpoint?.host == "telemetry-ingestion.us-phoenix-1.oraclecloud.com")
  }

  @Test("An explicit endpoint takes precedence over region")
  func explicitEndpointTakesPrecedence() throws {
    let client = try MonitoringClient(
      region: .phx,
      endpoint: "https://telemetry-ingestion.eu-frankfurt-1.oraclecloud.com",
      signer: NoopSigner()
    )
    #expect(client.endpoint?.host == "telemetry-ingestion.eu-frankfurt-1.oraclecloud.com")
  }

  @Test("Initializing with neither endpoint nor region throws missingRequiredParameter")
  func initWithoutEndpointOrRegionThrows() {
    #expect(throws: MonitoringError.self) {
      _ = try MonitoringClient(signer: NoopSigner())
    }
  }
}
