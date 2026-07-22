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
// Hermetic tests for OCILogHandler — no ~/.oci/config, no credentials, no
// network. `log(...)` is called directly (the classic LogHandler entry point
// swift-log itself calls), so these tests do not need `LoggingSystem.bootstrap`
// at all. That matters for the recursion-guard tests in particular:
// `LoggingSystem.bootstrap` is a process-wide, call-once gate, and this test
// binary hosts every other suite in the package — actually bootstrapping it
// here would leak into every `Logger(label:)` constructed anywhere else in the
// same test run. Instead each test constructs the exact handler a bootstrap
// would have handed out for the label under test and calls it directly:
// `Logger` does nothing else on the way in, so the guard being observed is the
// same one the real bootstrap path relies on.
//
// Both halves of the guard are covered:
//   * `excludedLoggerLabelsAlwaysContainTheSDKLabel` — the label list, and the
//     fact that a caller cannot remove the SDK's own label from it.
//   * `loggingFromInsideAFlushDoesNotRecurse` — the task-local, exercised
//     through a custom transport that logs each request under a label the
//     batcher has never heard of. This is the case a label list cannot cover,
//     and the one that self-amplifies without a re-entrancy flag.
//

import Foundation
import Logging
import Testing

@testable import OCIKit

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

// A no-op-ish signer: these tests exercise handler/batcher behavior, not
// signature correctness.
private struct StubSigner: Signer {
  func sign(_ req: inout URLRequest) throws {
    req.setValue(#"Signature version="1""#, forHTTPHeaderField: "Authorization")
  }
}

/// A "request logging" transport — the seam ``HTTPClient``'s own documentation
/// advertises for custom proxying, retry, or wire logging — that logs each
/// request through an ``OCILogHandler`` under a label the batcher has never
/// heard of. It is the shape that turns a label-only recursion guard into an
/// unbounded self-amplifying flush loop.
///
/// The handler is built inside the actor rather than handed in, because it has
/// to reference the very batcher this transport belongs to.
private actor WireLogger {
  private var handler: OCILogHandler?

  /// How many requests this transport was asked to log. Guards against a
  /// vacuous test: if this stays at zero, nothing ever logged from a flush.
  private(set) var attempts = 0

  /// Builds the handler that logs every request, for the batcher being wrapped.
  func attach(to batcher: OCILogBatcher, label: String) {
    handler = OCILogHandler(label: label, batcher: batcher)
  }

  /// Logs one request the way a wire-logging transport would.
  func logRequest(_ request: URLRequest) {
    attempts += 1
    handler?.log(
      level: .info,
      message: "POST \(request.url?.path ?? "")",
      metadata: nil,
      source: "http.wire",
      file: #filePath,
      function: #function,
      line: #line
    )
  }
}

struct OCILogHandlerTests {

  private func makeBatcher(
    flushInterval: TimeInterval = 0,
    retryConfig: RetryConfig? = nil,
    httpClient: HTTPClient
  ) throws -> OCILogBatcher {
    try OCILogBatcher(
      configuration: OCILogHandlerConfiguration(
        logId: "ocid1.log.oc1.phx.EXAMPLE",
        flushInterval: flushInterval,
        retryConfig: retryConfig
      ),
      region: .phx,
      signer: StubSigner(),
      httpClient: httpClient
    )
  }

  private func logLine(
    _ handler: OCILogHandler,
    level: Logger.Level = .info,
    message: Logger.Message = "hello",
    metadata: Logger.Metadata? = nil,
    source: String = "App"
  ) {
    handler.log(
      level: level,
      message: message,
      metadata: metadata,
      source: source,
      file: #filePath,
      function: #function,
      line: #line
    )
  }

  // MARK: - Rendering

  @Test("render lays out timestamp, level, label, metadata, source, and message like StreamLogHandler")
  func renderLayout() {
    let timestamp = Date(timeIntervalSince1970: 1_770_000_000)
    let rendered = OCILogHandler.render(
      timestamp: timestamp,
      level: .info,
      label: "com.example.orders",
      message: "order placed",
      metadata: ["orderId": "1234"],
      source: "Orders"
    )
    #expect(rendered == "\(timestamp.toRFC3339()) info com.example.orders : orderId=1234 [Orders] order placed")
  }

  @Test("render omits the metadata segment entirely when there is none")
  func renderWithoutMetadata() {
    let timestamp = Date(timeIntervalSince1970: 1_770_000_000)
    let rendered = OCILogHandler.render(
      timestamp: timestamp,
      level: .debug,
      label: "app",
      message: "hi",
      metadata: nil,
      source: "App"
    )
    #expect(rendered == "\(timestamp.toRFC3339()) debug app : [App] hi")
  }

  @Test("prettify sorts metadata by key so the rendered text is stable across runs")
  func prettifySortsByKey() {
    let text = OCILogHandler.prettify(["zeta": "1", "alpha": "2", "mid": "3"])
    #expect(text == "alpha=2 mid=3 zeta=1")
  }

  // MARK: - Metadata precedence (handler < provider < explicit)

  @Test("metadata merges handler, provider, and explicit values, with explicit taking precedence over provider over handler")
  func metadataPrecedence() async throws {
    let transport = OCILogRecordingTransport()
    let batcher = try makeBatcher(httpClient: await transport.makeClient())

    let handler = OCILogHandler(
      label: "com.example.app",
      batcher: batcher,
      metadata: ["shared": "handler", "handlerOnly": "h"],
      metadataProvider: Logger.MetadataProvider {
        ["shared": "provider", "providerOnly": "p"]
      }
    )

    logLine(handler, metadata: ["shared": "explicit"])
    await batcher.shutdown()

    let data = try await singleEntryData(transport)
    #expect(data.contains("handlerOnly=h"))
    #expect(data.contains("providerOnly=p"))
    #expect(data.contains("shared=explicit"))
    #expect(!data.contains("shared=handler"))
    #expect(!data.contains("shared=provider"))
  }

  @Test("with no explicit or provider metadata, only the handler's own metadata is rendered")
  func metadataFallsBackToHandlerOnly() async throws {
    let transport = OCILogRecordingTransport()
    let batcher = try makeBatcher(httpClient: await transport.makeClient())
    let handler = OCILogHandler(label: "com.example.app", batcher: batcher, metadata: ["handlerOnly": "h"])

    logLine(handler, metadata: nil)
    await batcher.shutdown()

    let data = try await singleEntryData(transport)
    #expect(data.contains("handlerOnly=h"))
  }

  // MARK: - Recursion guard

  @Test(
    "a handler for an excluded logger label (the default \"OCIKit\") never enqueues a record, even if the caller is the SDK's own signer logging on every request"
  )
  func excludedLabelNeverEnqueues() async throws {
    let transport = OCILogRecordingTransport()
    let batcher = try makeBatcher(httpClient: await transport.makeClient())
    let handler = OCILogHandler(label: "OCIKit", batcher: batcher)

    logLine(handler, level: .debug, message: "signingString: ...", source: "Signer")
    await batcher.shutdown()

    #expect(batcher.statistics.enqueued == 0)
    #expect(batcher.statistics.dropped == 0)
    let count = await transport.requests.count
    #expect(count == 0)
  }

  @Test("a non-excluded label's records are enqueued and shipped normally")
  func nonExcludedLabelEnqueuesNormally() async throws {
    let transport = OCILogRecordingTransport()
    let batcher = try makeBatcher(httpClient: await transport.makeClient())
    let handler = OCILogHandler(label: "com.example.app", batcher: batcher)

    logLine(handler)
    await batcher.shutdown()

    #expect(batcher.statistics.enqueued == 1)
    let count = await transport.requests.count
    #expect(count == 1)
  }

  @Test(
    "a caller-supplied exclusion set is added to the mandatory labels rather than replacing them, and emptying it afterwards cannot un-exclude them"
  )
  func excludedLoggerLabelsAlwaysContainTheSDKLabel() async throws {
    var configuration = OCILogHandlerConfiguration(
      logId: "ocid1.log.oc1.phx.EXAMPLE",
      flushInterval: 0,
      retryConfig: nil,
      excludedLoggerLabels: ["com.example.noisy"]
    )
    #expect(configuration.excludedLoggerLabels == ["com.example.noisy", "OCIKit"])

    // Even wiped after the fact, the mandatory labels stay excluded at use.
    configuration.excludedLoggerLabels = []

    let transport = OCILogRecordingTransport()
    let batcher = try OCILogBatcher(
      configuration: configuration,
      region: .phx,
      signer: StubSigner(),
      httpClient: await transport.makeClient()
    )
    #expect(batcher.isExcluded(loggerLabel: "OCIKit"))

    let handler = OCILogHandler(label: "OCIKit", batcher: batcher)
    logLine(handler, level: .debug, message: "signingString: ...", source: "Signer")
    await batcher.shutdown()

    #expect(batcher.statistics.enqueued == 0)
    let count = await transport.requests.count
    #expect(count == 0)
  }

  @Test(
    "a record logged from inside a flush — by a custom transport on the request path, under an unlisted label — is dropped instead of feeding the next flush"
  )
  func loggingFromInsideAFlushDoesNotRecurse() async throws {
    let transport = OCILogRecordingTransport()
    let recorder = await transport.makeClient()
    let wire = WireLogger()

    let batcher = try makeBatcher(
      httpClient: HTTPClient { request in
        await wire.logRequest(request)
        return try await recorder.data(request)
      }
    )
    await wire.attach(to: batcher, label: "http.wire")

    let application = OCILogHandler(label: "com.example.app", batcher: batcher)
    logLine(application, message: "the only application record")

    // Flushed explicitly, not via shutdown(): the hand-off stream is still open,
    // so a record the transport enqueues here really would be picked up and
    // shipped by the next flush, which is what makes the loop self-sustaining.
    await batcher.flush()

    // The transport really did log from inside the flush...
    #expect(await wire.attempts >= 1)
    // ...and that log went nowhere: one record in, one record enqueued.
    #expect(batcher.statistics.enqueued == 1)
    let duringFlush = await transport.requests.count
    #expect(duringFlush == 1)

    // Nothing was left behind to ship on the way out either.
    await batcher.shutdown()
    #expect(batcher.statistics.submitted == 1)
    let afterShutdown = await transport.requests.count
    #expect(afterShutdown == 1)
  }

  @Test("a failing flush is counted in statistics but produces no additional, re-entrant flush attempts")
  func failingFlushDoesNotRecurse() async throws {
    let transport = OCILogRecordingTransport()
    await transport.setResponse(
      status: 500,
      body: Data(#"{"code":"InternalError","message":"boom"}"#.utf8)
    )
    let batcher = try makeBatcher(httpClient: await transport.makeClient())
    let handler = OCILogHandler(label: "com.example.app", batcher: batcher)

    logLine(handler, message: "will fail to ship")
    await batcher.shutdown()

    #expect(batcher.statistics.flushFailures == 1)
    #expect(batcher.statistics.failed == 1)
    #expect(batcher.statistics.submitted == 0)
    #expect(batcher.statistics.lastFlushErrorDescription != nil)

    // Exactly the one attempt: a re-entrant bug would have produced more
    // requests than there were records logged.
    let count = await transport.requests.count
    #expect(count == 1)
  }

  // MARK: - Statistics forwarding

  @Test("OCILogHandler.statistics forwards the shared batcher's snapshot")
  func statisticsForwardsBatcher() async throws {
    let transport = OCILogRecordingTransport()
    let batcher = try makeBatcher(httpClient: await transport.makeClient())
    let handler = OCILogHandler(label: "com.example.app", batcher: batcher)

    logLine(handler)
    await batcher.shutdown()

    #expect(handler.statistics == batcher.statistics)
    #expect(handler.statistics.submitted == 1)
  }

  // MARK: - Helpers

  private func singleEntryData(_ transport: OCILogRecordingTransport) async throws -> String {
    let requests = await transport.requests
    let body = try #require(requests.first?.httpBody)
    let details = try JSONDecoder().decode(PutLogsDetails.self, from: body)
    return try #require(details.logEntryBatches.first?.entries.first?.data)
  }
}
