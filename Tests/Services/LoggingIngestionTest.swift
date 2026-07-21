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
// Credential-free unit tests for LoggingIngestion: router path/method/headers,
// model JSON encoding against the verified wire shape, and error descriptions.
// No network, no ~/.oci/config, no live OCI resources.
//

import Foundation
import Testing

@testable import OCIKit

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

// MARK: - Router Tests

struct LoggingIngestionRouterTests {

  @Test("putLogs path is /20200831/logs/<logId>/actions/push and method is POST")
  func putLogsPath() {
    let api = LoggingIngestionAPI.putLogs(logId: "ocid1.log.oc1.phx.EXAMPLE")

    #expect(api.path == "/20200831/logs/ocid1.log.oc1.phx.EXAMPLE/actions/push")
    #expect(api.method == .post)
  }

  @Test("putLogs has no query items")
  func putLogsNoQueryItems() {
    let api = LoggingIngestionAPI.putLogs(logId: "ocid1.log.oc1.phx.EXAMPLE")

    #expect(api.queryItems == nil)
  }

  @Test("putLogs headers include opc-request-id and timestamp-opc-agent-processing when provided")
  func putLogsHeadersWithBothProvided() {
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let agentTime = iso.date(from: "2026-02-02T02:40:00.123Z")!

    let api = LoggingIngestionAPI.putLogs(
      logId: "ocid1.log.oc1.phx.EXAMPLE",
      opcRequestId: "req-abc",
      timestampOpcAgentProcessing: agentTime
    )

    let headers = api.headers
    #expect(headers?["opc-request-id"] == "req-abc")
    #expect(headers?["timestamp-opc-agent-processing"] == "2026-02-02T02:40:00.123Z")
  }

  @Test("putLogs headers include only opc-request-id when the timestamp is absent")
  func putLogsHeadersWithOnlyOpcRequestId() {
    let api = LoggingIngestionAPI.putLogs(
      logId: "ocid1.log.oc1.phx.EXAMPLE",
      opcRequestId: "req-abc"
    )

    let headers = api.headers
    #expect(headers?["opc-request-id"] == "req-abc")
    #expect(headers?["timestamp-opc-agent-processing"] == nil)
  }

  @Test("putLogs headers are nil when neither optional header is provided")
  func putLogsNoHeaders() {
    let api = LoggingIngestionAPI.putLogs(logId: "ocid1.log.oc1.phx.EXAMPLE")

    #expect(api.headers == nil)
  }
}

// MARK: - Model Encoding Tests

struct LoggingIngestionModelEncodingTests {

  /// Fixed RFC3339-with-milliseconds instant shared by these tests, matching
  /// the format the wire contract expects (see OBSERVABILITY.md §2 and BRIEF.md).
  private static let fixedTime: Date = {
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return iso.date(from: "2026-02-02T02:40:00.123Z")!
  }()

  private func encodedJSONObject(_ details: PutLogsDetails) throws -> [String: Any] {
    let data = try JSONEncoder().encode(details)
    let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    return object ?? [:]
  }

  @Test("PutLogsDetails encodes the exact live-verified wire shape (no subject, no per-entry time)")
  func putLogsDetailsEncodesMinimalWireShape() throws {
    let details = PutLogsDetails(
      logEntryBatches: [
        LogEntryBatch(
          entries: [LogEntry(data: "hello", id: "fixed-id")],
          source: "probe-host",
          type: "com.oraclecloud.probe",
          defaultlogentrytime: Self.fixedTime
        )
      ]
    )

    let data = try JSONEncoder().encode(details)
    let json = String(data: data, encoding: .utf8)!

    // Round-trip the literal shape captured live in the brief:
    // {"specversion":"1.0","logEntryBatches":[{"entries":[{"data":"...","id":"..."}],
    //  "source":"...","type":"...","defaultlogentrytime":"<RFC3339 ms>"}]}
    #expect(json.contains(#""specversion":"1.0""#))
    #expect(json.contains(#""defaultlogentrytime":"2026-02-02T02:40:00.123Z""#))
    #expect(json.contains(#""source":"probe-host""#))
    #expect(json.contains(#""type":"com.oraclecloud.probe""#))
    #expect(json.contains(#""data":"hello""#))
    #expect(json.contains(#""id":"fixed-id""#))
    // Optional fields must be omitted entirely, not encoded as null.
    #expect(!json.contains("subject"))
    #expect(!json.contains(#""time""#))
  }

  @Test("PutLogsDetails encodes specversion, logEntryBatches, and entries as the correct JSON types")
  func putLogsDetailsEncodesShapeStructurally() throws {
    let details = PutLogsDetails(
      logEntryBatches: [
        LogEntryBatch(
          entries: [LogEntry(data: "hello", id: "fixed-id")],
          source: "probe-host",
          type: "com.oraclecloud.probe",
          defaultlogentrytime: Self.fixedTime
        )
      ]
    )

    let object = try encodedJSONObject(details)
    #expect(object["specversion"] as? String == "1.0")

    let batches = object["logEntryBatches"] as? [[String: Any]]
    #expect(batches?.count == 1)
    #expect(batches?.first?["source"] as? String == "probe-host")
    #expect(batches?.first?["type"] as? String == "com.oraclecloud.probe")
    #expect(batches?.first?["defaultlogentrytime"] as? String == "2026-02-02T02:40:00.123Z")
    #expect(batches?.first?["subject"] == nil)

    let entries = batches?.first?["entries"] as? [[String: Any]]
    #expect(entries?.count == 1)
    #expect(entries?.first?["data"] as? String == "hello")
    #expect(entries?.first?["id"] as? String == "fixed-id")
    #expect(entries?.first?["time"] == nil)
  }

  @Test("LogEntryBatch encodes subject when provided")
  func logEntryBatchEncodesSubjectWhenPresent() throws {
    let batch = LogEntryBatch(
      entries: [LogEntry(data: "hello", id: "fixed-id")],
      source: "probe-host",
      type: "com.oraclecloud.probe",
      subject: "/var/log/application.log",
      defaultlogentrytime: Self.fixedTime
    )

    let data = try JSONEncoder().encode(batch)
    let json = String(data: data, encoding: .utf8)!

    #expect(json.contains(#""subject":"\/var\/log\/application.log""#) || json.contains(#""subject":"/var/log/application.log""#))
  }

  @Test("LogEntry encodes its own time when provided, overriding the batch default")
  func logEntryEncodesOwnTimeWhenPresent() throws {
    let entryIso = ISO8601DateFormatter()
    entryIso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let entryTime = entryIso.date(from: "2026-02-02T02:41:30.500Z")!

    let entry = LogEntry(data: "hello", id: "fixed-id", time: entryTime)

    let data = try JSONEncoder().encode(entry)
    let json = String(data: data, encoding: .utf8)!

    #expect(json.contains(#""time":"2026-02-02T02:41:30.500Z""#))
  }

  @Test("LogEntry defaults id to a freshly generated UUID string")
  func logEntryDefaultsIdToUUID() {
    let entry = LogEntry(data: "hello")

    #expect(UUID(uuidString: entry.id) != nil)
    #expect(entry.time == nil)
  }

  @Test("PutLogsDetails defaults specversion to 1.0")
  func putLogsDetailsDefaultsSpecVersion() {
    let details = PutLogsDetails(logEntryBatches: [])

    #expect(details.specversion == "1.0")
  }
}

// MARK: - Error Tests

struct LoggingIngestionErrorTests {

  @Test("LoggingIngestionError descriptions are correct")
  func errorDescriptions() {
    let invalidResponse = LoggingIngestionError.invalidResponse("Bad response")
    #expect(invalidResponse.localizedDescription.contains("Bad response"))

    let invalidURL = LoggingIngestionError.invalidURL("https://bad.url")
    #expect(invalidURL.localizedDescription.contains("https://bad.url"))

    let jsonEncodingError = LoggingIngestionError.jsonEncodingError("could not encode")
    #expect(jsonEncodingError.localizedDescription.contains("could not encode"))

    let missingParam = LoggingIngestionError.missingRequiredParameter("logId")
    #expect(missingParam.localizedDescription.contains("logId"))

    let unexpectedStatus = LoggingIngestionError.unexpectedStatusCode(404, "logId not found")
    #expect(unexpectedStatus.localizedDescription.contains("404"))
    #expect(unexpectedStatus.localizedDescription.contains("logId not found"))
  }
}

// MARK: - Client Initialization Tests

struct LoggingIngestionClientInitTests {

  @Test("Client initializes with region and derives the ingestion.logging endpoint")
  func initWithRegion() throws {
    let client = try LoggingIngestClient(region: .phx, signer: NoopSigner())

    #expect(client.endpoint?.absoluteString.contains("ingestion.logging.us-phoenix-1") == true)
  }

  @Test("Client initializes with a custom endpoint, which takes precedence over region")
  func initWithEndpoint() throws {
    let client = try LoggingIngestClient(
      endpoint: "https://custom.ingestion.endpoint.example",
      signer: NoopSigner()
    )

    #expect(client.endpoint?.absoluteString == "https://custom.ingestion.endpoint.example")
  }

  @Test("Client throws missingRequiredParameter when neither region nor endpoint is provided")
  func initThrowsWithoutRegionOrEndpoint() {
    #expect(throws: LoggingIngestionError.self) {
      _ = try LoggingIngestClient(signer: NoopSigner())
    }
  }
}

/// A signer that performs no signing. Used only to exercise client
/// initialization logic (region/endpoint precedence), never a network call.
private struct NoopSigner: Signer {
  func sign(_ req: inout URLRequest) throws {}
}
