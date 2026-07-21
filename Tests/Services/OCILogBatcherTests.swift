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
// Hermetic tests for OCILogBatcher — no ~/.oci/config, no credentials, no
// network. Every test injects an ``OCILogRecordingTransport`` in place of
// ``HTTPClient/live``, so nothing here depends on wall-clock timing racing a
// background task: threshold/ordering/overflow tests synchronize with the
// batcher's drain task through ``OCILogRecordingTransport``'s continuation-based
// waiters (``OCILogRecordingTransport/waitForRequests(_:)``,
// ``OCILogRecordingTransport/waitUntilBlocked()``) or through
// ``OCILogBatcher/shutdown()``'s guaranteed terminal drain, never through a
// fixed-duration `Task.sleep` in the test itself. The one exception is the
// interval-flush test, which necessarily exercises the batcher's own
// `Task.sleep`-based ticker — it uses a very short interval and still
// synchronizes via a continuation rather than guessing a sleep duration.
//

import Foundation
import Logging
import Testing

@testable import OCIKit

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

// A no-op-ish signer: these tests exercise batching/flushing, not signature
// correctness.
private struct StubSigner: Signer {
  func sign(_ req: inout URLRequest) throws {
    req.setValue(#"Signature version="1""#, forHTTPHeaderField: "Authorization")
  }
}

/// A recording `HTTPClient` transport with a gate, used to deterministically
/// synchronize a test with the batcher's drain task without sleeping.
///
/// - ``waitForRequests(_:)`` resolves as soon as at least `n` requests have
///   arrived, however long that takes — no polling, no fixed sleep.
/// - ``close()`` / ``open()`` let a test suspend the transport mid-flush (so
///   the drain task is provably not reading the hand-off stream) and later
///   release it. ``waitUntilBlocked()`` resolves exactly when a request is
///   parked behind a closed gate.
actor OCILogRecordingTransport {
  private(set) var requests: [URLRequest] = []

  private var isOpen = true
  private var pendingRelease: CheckedContinuation<Void, Never>?
  private var isBlocked = false
  private var blockedWaiters: [CheckedContinuation<Void, Never>] = []
  private var countWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

  private var responseStatus = 200
  private var responseBody = Data()

  /// An `HTTPClient` backed by this recorder.
  func makeClient() -> HTTPClient {
    HTTPClient { [self] request in
      await self.handle(request)
    }
  }

  /// Sets the status code and body every subsequent request receives.
  func setResponse(status: Int, body: Data = Data()) {
    responseStatus = status
    responseBody = body
  }

  /// Closes the gate: the next request to arrive suspends until ``open()`` is called.
  func close() {
    isOpen = false
  }

  /// Opens the gate and releases a request currently suspended behind it, if any.
  func open() {
    isOpen = true
    isBlocked = false
    if let pendingRelease {
      self.pendingRelease = nil
      pendingRelease.resume()
    }
  }

  /// Suspends until at least `n` requests have been recorded.
  func waitForRequests(_ n: Int) async {
    if requests.count >= n { return }
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      countWaiters.append((n, continuation))
    }
  }

  /// Suspends until a request is parked behind a closed gate.
  func waitUntilBlocked() async {
    if isBlocked { return }
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      blockedWaiters.append(continuation)
    }
  }

  private func handle(_ request: URLRequest) async -> (Data, URLResponse) {
    requests.append(request)
    notifyCountWaiters()

    if !isOpen {
      await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        // Recorded here, inside the closure that sets up the suspension: by
        // the time this closure returns, the caller (the batcher's drain
        // task) is guaranteed to actually suspend, so `waitUntilBlocked()`
        // callers never observe a false "blocked" state.
        pendingRelease = continuation
        isBlocked = true
        for waiter in blockedWaiters { waiter.resume() }
        blockedWaiters.removeAll()
      }
    }

    let url = request.url ?? URL(string: "https://example.invalid")!
    let response = HTTPURLResponse(
      url: url,
      statusCode: responseStatus,
      httpVersion: "HTTP/1.1",
      headerFields: [:]
    )!
    return (responseBody, response)
  }

  private func notifyCountWaiters() {
    countWaiters.removeAll { entry in
      guard requests.count >= entry.count else { return false }
      entry.continuation.resume()
      return true
    }
  }
}

struct OCILogBatcherTests {

  private func makeBatcher(
    source: String = "unit-test-host",
    type: String = "com.oraclecloud.unittest",
    subject: String? = nil,
    flushInterval: TimeInterval = 0,
    flushSizeThreshold: Int = OCILogHandlerConfiguration.defaultFlushSizeThreshold,
    bufferCapacity: Int = OCILogHandlerConfiguration.defaultBufferCapacity,
    maxEntryLength: Int = OCILogHandlerConfiguration.defaultMaxEntryLength,
    retryConfig: RetryConfig? = nil,
    httpClient: HTTPClient
  ) throws -> OCILogBatcher {
    try OCILogBatcher(
      configuration: OCILogHandlerConfiguration(
        logId: "ocid1.log.oc1.phx.EXAMPLE",
        source: source,
        type: type,
        subject: subject,
        flushInterval: flushInterval,
        flushSizeThreshold: flushSizeThreshold,
        bufferCapacity: bufferCapacity,
        maxEntryLength: maxEntryLength,
        retryConfig: retryConfig
      ),
      region: .phx,
      signer: StubSigner(),
      httpClient: httpClient
    )
  }

  // MARK: - flush()

  @Test("flush() on an empty buffer performs no PutLogs request")
  func flushOnEmptyBufferIsNoOp() async throws {
    let transport = OCILogRecordingTransport()
    let batcher = try makeBatcher(httpClient: await transport.makeClient())

    await batcher.flush()

    let count = await transport.requests.count
    #expect(count == 0)
    await batcher.shutdown()
  }

  // MARK: - Size-threshold flush

  @Test("crossing the size threshold flushes immediately, leaving the remainder for shutdown's drain")
  func sizeThresholdFlushUploadsOnceThresholdIsCrossed() async throws {
    let transport = OCILogRecordingTransport()
    let data1 = String(repeating: "A", count: 50)
    let data2 = String(repeating: "B", count: 50)
    let data3 = String(repeating: "C", count: 50)

    // Threshold crosses exactly after the second record is appended.
    let batcher = try makeBatcher(
      flushSizeThreshold: data1.utf8.count + data2.utf8.count,
      httpClient: await transport.makeClient()
    )

    batcher.enqueue(OCILogRecord(data: data1))
    batcher.enqueue(OCILogRecord(data: data2))
    await transport.waitForRequests(1)

    let firstBatch = try requireSingleBatch(await transport.requests[0])
    #expect(firstBatch.entries.map(\.data) == [data1, data2])

    // The third record was under threshold, so it stays buffered until shutdown.
    batcher.enqueue(OCILogRecord(data: data3))
    await batcher.shutdown()

    let requests = await transport.requests
    #expect(requests.count == 2)
    let secondBatch = try requireSingleBatch(requests[1])
    #expect(secondBatch.entries.map(\.data) == [data3])
  }

  // MARK: - Interval flush

  @Test("a buffered record is flushed once the configured interval elapses, even under the size threshold")
  func intervalFlushUploadsAfterTheConfiguredInterval() async throws {
    let transport = OCILogRecordingTransport()
    let batcher = try makeBatcher(
      flushInterval: 0.1,
      flushSizeThreshold: 1 << 30,
      httpClient: await transport.makeClient()
    )

    batcher.enqueue(OCILogRecord(data: "ticked"))
    await transport.waitForRequests(1)

    let batch = try requireSingleBatch(await transport.requests[0])
    #expect(batch.entries.map(\.data) == ["ticked"])

    await batcher.shutdown()
    let count = await transport.requests.count
    #expect(count == 1)  // nothing left to flush a second time on shutdown
  }

  // MARK: - Ordering + shutdown drain

  @Test("shutdown() drains everything still buffered, in enqueue order, as a single flush")
  func shutdownDrainsBufferedRecordsInOrder() async throws {
    let transport = OCILogRecordingTransport()
    let batcher = try makeBatcher(
      flushSizeThreshold: 1 << 30,  // never triggers on its own
      httpClient: await transport.makeClient()
    )

    let expected = (0..<5).map { "record-\($0)" }
    for text in expected {
      batcher.enqueue(OCILogRecord(data: text))
    }

    await batcher.shutdown()

    let requests = await transport.requests
    #expect(requests.count == 1)
    let batch = try requireSingleBatch(requests[0])
    #expect(batch.entries.map(\.data) == expected)
  }

  // MARK: - Overflow drop accounting

  @Test("buffer overflow drops only the newest records once bufferCapacity is exceeded, and counts them")
  func bufferOverflowDropsNewestRecordsAndCountsThem() async throws {
    let transport = OCILogRecordingTransport()
    await transport.close()

    let batcher = try makeBatcher(
      flushSizeThreshold: 1,  // any single record crosses the threshold
      bufferCapacity: 3,
      httpClient: await transport.makeClient()
    )

    // This record is picked up by the drain task, crosses the threshold, and
    // blocks inside the (closed) transport gate -- so the drain task is
    // provably not reading the hand-off stream while the burst below runs.
    batcher.enqueue(OCILogRecord(data: "first"))
    await transport.waitUntilBlocked()

    // Only `bufferCapacity` (3) of these 6 fit in the hand-off stream's
    // buffer; `.bufferingOldest` keeps the oldest and drops the newest.
    for i in 0..<6 {
      batcher.enqueue(OCILogRecord(data: "overflow-\(i)"))
    }

    #expect(batcher.statistics.enqueued == 4)  // "first" + the 3 that fit
    #expect(batcher.statistics.dropped == 3)

    await transport.open()
    await transport.waitForRequests(4)  // "first" plus the 3 admitted records
    await batcher.shutdown()

    let requests = await transport.requests
    #expect(requests.count == 4)
    #expect(batcher.statistics.dropped == 3)
    #expect(batcher.statistics.submitted == 4)

    // The three admitted records are exactly the oldest three of the burst.
    let shippedData = try requests.dropFirst().map { try requireSingleBatch($0).entries.map(\.data) }.flatMap { $0 }
    #expect(shippedData == ["overflow-0", "overflow-1", "overflow-2"])
  }

  // MARK: - Long-message splitting (static split(_:maxLength:))

  @Test("split returns the original string unchanged when it already fits, including exactly at the boundary")
  func splitFitsUnchanged() {
    #expect(OCILogBatcher.split("hello", maxLength: 100) == ["hello"])
    #expect(OCILogBatcher.split("hello", maxLength: 5) == ["hello"])
  }

  @Test("split breaks a string one character past the boundary into two ordered chunks")
  func splitOneCharacterPastBoundary() {
    let data = String(repeating: "x", count: 5) + "y"
    let chunks = OCILogBatcher.split(data, maxLength: 5)
    #expect(chunks == [String(repeating: "x", count: 5), "y"])
    #expect(chunks.joined() == data)
  }

  @Test("split at the service's default 9,900-character entry boundary reconstructs the original message")
  func splitAtServiceEntryBoundary() {
    let maxLength = OCILogHandlerConfiguration.defaultMaxEntryLength  // 9,900
    let totalLength = OCILogHandlerConfiguration.serviceEntryLengthLimit + 50  // 10,050
    let data = (0..<totalLength).map { String($0 % 10) }.joined()

    let chunks = OCILogBatcher.split(data, maxLength: maxLength)

    #expect(chunks.count == 2)
    #expect(chunks[0].count == maxLength)
    #expect(chunks[1].count == totalLength - maxLength)
    #expect(chunks.joined() == data)
  }

  @Test("split with a non-positive maxLength returns the original string unchanged")
  func splitNonPositiveMaxLengthIsUnchanged() {
    #expect(OCILogBatcher.split("hello", maxLength: 0) == ["hello"])
    #expect(OCILogBatcher.split("hello", maxLength: -1) == ["hello"])
  }

  @Test("a record longer than maxEntryLength is split into multiple entries sharing the record's time")
  func longRecordIsSplitAcrossEntriesOnTheWire() async throws {
    let transport = OCILogRecordingTransport()
    let maxEntryLength = 40
    let batcher = try makeBatcher(
      flushSizeThreshold: 1 << 30,
      maxEntryLength: maxEntryLength,
      httpClient: await transport.makeClient()
    )

    let time = Date(timeIntervalSince1970: 1_770_000_000)
    let longData = String(repeating: "x", count: maxEntryLength * 2 + 5)  // 85 chars -> 3 chunks
    batcher.enqueue(OCILogRecord(data: longData, time: time))

    await batcher.shutdown()

    let requests = await transport.requests
    #expect(requests.count == 1)
    let batch = try requireSingleBatch(requests[0])

    #expect(batch.entries.count == 3)
    #expect(batch.entries.map(\.data).joined() == longData)
    #expect(Set(batch.entries.map(\.id)).count == batch.entries.count)  // unique ids
    #expect(batch.entries.allSatisfy { $0.time == time.toRFC3339() })
  }

  // MARK: - Wire shape

  @Test("the flushed request decodes back to a PutLogsDetails matching the configured source/type/subject")
  func wireShapeMatchesConfiguration() async throws {
    let transport = OCILogRecordingTransport()
    let recordTime = Date(timeIntervalSince1970: 1_770_000_100.250)
    let batcher = try makeBatcher(
      source: "unit-test-host",
      type: "com.oraclecloud.unittest",
      subject: "unit-test-subject",
      httpClient: await transport.makeClient()
    )

    batcher.enqueue(OCILogRecord(data: "hello wire shape", time: recordTime))
    await batcher.shutdown()

    let requests = await transport.requests
    #expect(requests.count == 1)
    let req = try #require(requests.first)
    #expect(req.httpMethod == "POST")
    #expect(req.value(forHTTPHeaderField: "Content-Type") == "application/json")

    let body = try #require(req.httpBody)
    let details = try JSONDecoder().decode(PutLogsDetails.self, from: body)
    #expect(details.specversion == "1.0")

    let batch = try #require(details.logEntryBatches.first)
    #expect(batch.source == "unit-test-host")
    #expect(batch.type == "com.oraclecloud.unittest")
    #expect(batch.subject == "unit-test-subject")

    let entry = try #require(batch.entries.first)
    #expect(entry.data == "hello wire shape")
    #expect(entry.time == recordTime.toRFC3339())
    #expect(!entry.id.isEmpty)
  }

  // MARK: - Helpers

  private func requireSingleBatch(_ request: URLRequest) throws -> LogEntryBatch {
    let body = try #require(request.httpBody)
    let details = try JSONDecoder().decode(PutLogsDetails.self, from: body)
    return try #require(details.logEntryBatches.first)
  }
}
