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
// Hermetic tests for retry support (issue #78) — no credentials, no network.
// A scripted transport returns a canned sequence of responses/errors, one per
// attempt, so attempt counts, per-attempt re-signing, 401 refresh semantics,
// and Retry-After handling are all asserted deterministically.
//

import Foundation
import Testing

@testable import OCIKit

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

// MARK: - Test doubles

/// One scripted transport outcome per attempt.
private enum ScriptStep {
  case response(status: Int, headers: [String: String], body: Data)
  case failure(any Error)

  static func status(_ code: Int) -> ScriptStep { .response(status: code, headers: [:], body: Data()) }
}

/// Pops one scripted step per request and records every request it saw.
private actor ScriptedTransport {
  private var steps: [ScriptStep]
  private(set) var requests: [URLRequest] = []

  init(_ steps: [ScriptStep]) { self.steps = steps }

  var attemptCount: Int { requests.count }

  func next(for request: URLRequest) throws -> (Data, URLResponse) {
    requests.append(request)
    guard !steps.isEmpty else {
      // A test bug (more attempts than scripted) must fail fast, not loop.
      throw URLError(.unsupportedURL)
    }
    switch steps.removeFirst() {
    case .response(let status, let headers, let body):
      let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
      return (body, response)
    case .failure(let error):
      throw error
    }
  }
}

extension HTTPClient {
  fileprivate static func scripted(_ transport: ScriptedTransport) -> HTTPClient {
    HTTPClient { request in try await transport.next(for: request) }
  }
}

/// Stamps an incrementing attempt number so tests can prove every attempt was re-signed.
private final class CountingSigner: Signer, @unchecked Sendable {
  private let lock = NSLock()
  private var count = 0

  func sign(_ req: inout URLRequest) throws {
    lock.lock()
    defer { lock.unlock() }
    count += 1
    req.setValue("attempt-\(count)", forHTTPHeaderField: "X-Test-Attempt")
  }

  var signCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return count
  }
}

/// A refreshable signer that counts forceRefresh() calls.
private final class RefreshCountingSigner: RefreshableSigner, @unchecked Sendable {
  private let lock = NSLock()
  private var refreshes = 0

  func sign(_ req: inout URLRequest) throws {
    req.setValue(#"Signature version="1""#, forHTTPHeaderField: "Authorization")
  }

  func forceRefresh() throws {
    lock.lock()
    defer { lock.unlock() }
    refreshes += 1
  }

  var refreshCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return refreshes
  }
}

private struct PlainSigner: Signer {
  func sign(_ req: inout URLRequest) throws {
    req.setValue(#"Signature version="1""#, forHTTPHeaderField: "Authorization")
  }
}

/// Millisecond-scale delays keep the suite fast while exercising the real sleep path.
private let fastRetry = RetryConfig(maxAttempts: 3, baseDelay: 0.001, maxDelay: 0.005)

private func makeRequest() -> URLRequest {
  URLRequest(url: URL(string: "https://objectstorage.us-ashburn-1.oraclecloud.com/n")!)
}

// MARK: - RetryConfig unit tests

struct RetryConfigTests {

  @Test("default configuration mirrors the Python SDK's default strategy")
  func defaults() {
    let config = RetryConfig.default
    #expect(config.maxAttempts == 8)
    #expect(config.baseDelay == 1)
    #expect(config.maxDelay == 30)
    #expect(config.exponentialGrowthFactor == 2)
    #expect(config.maxCumulativeDelay == 600)
    #expect(config.retryableStatusCodes == [429, 500, 502, 503, 504])
    #expect(config.retriesOnConnectionErrors)
  }

  @Test("maxAttempts is clamped to at least one attempt")
  func maxAttemptsClamped() {
    #expect(RetryConfig(maxAttempts: 0).maxAttempts == 1)
    #expect(RetryConfig(maxAttempts: -5).maxAttempts == 1)
  }

  @Test("delay applies full jitter within the capped exponential bound")
  func delayBounds() {
    let config = RetryConfig(baseDelay: 1, maxDelay: 30, exponentialGrowthFactor: 2)
    for _ in 0..<100 {
      #expect((0...1).contains(config.delay(forAttempt: 1)))
      #expect((0...4).contains(config.delay(forAttempt: 3)))
      #expect((0...30).contains(config.delay(forAttempt: 10)))  // capped at maxDelay
    }
  }

  @Test("delay honors a server-provided Retry-After verbatim, without jitter")
  func delayHonorsRetryAfter() {
    let config = RetryConfig(baseDelay: 1, maxDelay: 30)
    #expect(config.delay(forAttempt: 1, retryAfter: 12.5) == 12.5)
    // Server instruction wins even beyond maxDelay.
    #expect(config.delay(forAttempt: 1, retryAfter: 60) == 60)
  }

  @Test("retryAfterSeconds parses delta-seconds and rejects HTTP-dates and garbage")
  func retryAfterParsing() {
    #expect(RetryConfig.retryAfterSeconds(from: "30") == 30)
    #expect(RetryConfig.retryAfterSeconds(from: " 5 ") == 5)
    #expect(RetryConfig.retryAfterSeconds(from: "1.5") == 1.5)
    #expect(RetryConfig.retryAfterSeconds(from: "Wed, 21 Oct 2026 07:28:00 GMT") == nil)
    #expect(RetryConfig.retryAfterSeconds(from: "-1") == nil)
    #expect(RetryConfig.retryAfterSeconds(from: "") == nil)
  }

  @Test("isTransient classifies URLError codes and respects retriesOnConnectionErrors")
  func transientClassification() {
    let config = RetryConfig()
    #expect(config.isTransient(URLError(.timedOut)))
    #expect(config.isTransient(URLError(.networkConnectionLost)))
    #expect(config.isTransient(URLError(.cannotConnectToHost)))
    #expect(!config.isTransient(URLError(.cancelled)))
    #expect(!config.isTransient(URLError(.badURL)))
    #expect(!config.isTransient(ConfigErrors.missingConfig))

    let noConnectionRetries = RetryConfig(retriesOnConnectionErrors: false)
    #expect(!noConnectionRetries.isTransient(URLError(.timedOut)))
  }
}

// MARK: - HTTPClient.send retry-loop tests

struct HTTPClientRetryTests {

  @Test("429 then 200: retries and succeeds on the second attempt")
  func retriesOn429() async throws {
    let transport = ScriptedTransport([.status(429), .status(200)])
    let (_, response) = try await HTTPClient.scripted(transport).send(makeRequest(), signer: PlainSigner(), retry: fastRetry, logger: logger)

    #expect((response as? HTTPURLResponse)?.statusCode == 200)
    #expect(await transport.attemptCount == 2)
  }

  @Test("503, 503 then 200: keeps retrying while the budget allows")
  func retriesOn503() async throws {
    let transport = ScriptedTransport([.status(503), .status(503), .status(200)])
    let (_, response) = try await HTTPClient.scripted(transport).send(makeRequest(), signer: PlainSigner(), retry: fastRetry, logger: logger)

    #expect((response as? HTTPURLResponse)?.statusCode == 200)
    #expect(await transport.attemptCount == 3)
  }

  @Test("attempt budget exhausted: the last response is returned unchanged")
  func budgetExhausted() async throws {
    let transport = ScriptedTransport([.status(503), .status(503), .status(503)])
    let (_, response) = try await HTTPClient.scripted(transport).send(makeRequest(), signer: PlainSigner(), retry: fastRetry, logger: logger)

    #expect((response as? HTTPURLResponse)?.statusCode == 503)
    #expect(await transport.attemptCount == 3)  // == maxAttempts
  }

  @Test("nil retry config performs exactly one attempt (historical behavior)")
  func nilConfigSingleAttempt() async throws {
    let transport = ScriptedTransport([.status(503), .status(200)])
    let (_, response) = try await HTTPClient.scripted(transport).send(makeRequest(), signer: PlainSigner(), retry: nil, logger: logger)

    #expect((response as? HTTPURLResponse)?.statusCode == 503)
    #expect(await transport.attemptCount == 1)
  }

  @Test("non-retryable status (400) is returned immediately")
  func nonRetryableStatus() async throws {
    let transport = ScriptedTransport([.status(400), .status(200)])
    let (_, response) = try await HTTPClient.scripted(transport).send(makeRequest(), signer: PlainSigner(), retry: fastRetry, logger: logger)

    #expect((response as? HTTPURLResponse)?.statusCode == 400)
    #expect(await transport.attemptCount == 1)
  }

  @Test("transient URLError (timedOut) is retried; the request eventually succeeds")
  func transientErrorRetried() async throws {
    let transport = ScriptedTransport([.failure(URLError(.timedOut)), .status(200)])
    let (_, response) = try await HTTPClient.scripted(transport).send(makeRequest(), signer: PlainSigner(), retry: fastRetry, logger: logger)

    #expect((response as? HTTPURLResponse)?.statusCode == 200)
    #expect(await transport.attemptCount == 2)
  }

  @Test("transient errors on every attempt: the last error is rethrown")
  func transientErrorsExhaustBudget() async throws {
    let transport = ScriptedTransport([.failure(URLError(.timedOut)), .failure(URLError(.timedOut)), .failure(URLError(.timedOut))])
    await #expect(throws: URLError.self) {
      _ = try await HTTPClient.scripted(transport).send(makeRequest(), signer: PlainSigner(), retry: fastRetry, logger: logger)
    }
    #expect(await transport.attemptCount == 3)
  }

  @Test("non-transient error (cancelled) is rethrown immediately, no retry")
  func nonTransientErrorRethrown() async throws {
    let transport = ScriptedTransport([.failure(URLError(.cancelled)), .status(200)])
    await #expect(throws: URLError.self) {
      _ = try await HTTPClient.scripted(transport).send(makeRequest(), signer: PlainSigner(), retry: fastRetry, logger: logger)
    }
    #expect(await transport.attemptCount == 1)
  }

  @Test("every attempt is signed afresh from the pristine request")
  func resignsEveryAttempt() async throws {
    let signer = CountingSigner()
    let transport = ScriptedTransport([.status(503), .status(503), .status(200)])
    _ = try await HTTPClient.scripted(transport).send(makeRequest(), signer: signer, retry: fastRetry, logger: logger)

    #expect(signer.signCount == 3)
    let stamps = await transport.requests.map { $0.value(forHTTPHeaderField: "X-Test-Attempt") }
    // Each attempt carries exactly its own stamp — proof the signature was
    // rebuilt from the unsigned request rather than replayed or layered.
    #expect(stamps == ["attempt-1", "attempt-2", "attempt-3"])
  }

  @Test("401 with a refreshable signer: forces one refresh and retries once, even with retry disabled")
  func refreshesOn401() async throws {
    let signer = RefreshCountingSigner()
    let transport = ScriptedTransport([.status(401), .status(200)])
    let (_, response) = try await HTTPClient.scripted(transport).send(makeRequest(), signer: signer, retry: nil, logger: logger)

    #expect((response as? HTTPURLResponse)?.statusCode == 200)
    #expect(await transport.attemptCount == 2)
    #expect(signer.refreshCount == 1)
  }

  @Test("second consecutive 401 is returned as-is — refresh-and-retry happens only once")
  func secondConsecutive401Returned() async throws {
    let signer = RefreshCountingSigner()
    let transport = ScriptedTransport([.status(401), .status(401)])
    let (_, response) = try await HTTPClient.scripted(transport).send(makeRequest(), signer: signer, retry: fastRetry, logger: logger)

    #expect((response as? HTTPURLResponse)?.statusCode == 401)
    #expect(await transport.attemptCount == 2)
    #expect(signer.refreshCount == 1)
  }

  @Test("401 with a non-refreshable signer is returned immediately")
  func noRefreshForPlainSigner() async throws {
    let transport = ScriptedTransport([.status(401), .status(200)])
    let (_, response) = try await HTTPClient.scripted(transport).send(makeRequest(), signer: PlainSigner(), retry: fastRetry, logger: logger)

    #expect((response as? HTTPURLResponse)?.statusCode == 401)
    #expect(await transport.attemptCount == 1)
  }

  @Test("Retry-After response header is honored on a 429")
  func retryAfterHonored() async throws {
    let transport = ScriptedTransport([
      .response(status: 429, headers: ["Retry-After": "0"], body: Data()),
      .status(200),
    ])
    let (_, response) = try await HTTPClient.scripted(transport).send(makeRequest(), signer: PlainSigner(), retry: fastRetry, logger: logger)

    #expect((response as? HTTPURLResponse)?.statusCode == 200)
    #expect(await transport.attemptCount == 2)
  }

  @Test("unsigned requests (signer: nil) go through the retry loop without an Authorization header")
  func unsignedRequestRetries() async throws {
    let transport = ScriptedTransport([.status(503), .status(200)])
    let (_, response) = try await HTTPClient.scripted(transport).send(makeRequest(), signer: nil, retry: fastRetry, logger: logger)

    #expect((response as? HTTPURLResponse)?.statusCode == 200)
    #expect(await transport.attemptCount == 2)
    let authHeaders = await transport.requests.map { $0.value(forHTTPHeaderField: "Authorization") }
    #expect(authHeaders == [nil, nil])
  }
}
