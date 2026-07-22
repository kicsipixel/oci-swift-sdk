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
// Credential-free unit tests for issue #91 (OCIMetricsFactory), test groups
// 2, 4 and 5:
//   • chunking a large registry snapshot at the service's 50-stream-per-request
//     limit (OCIMetricsExporterChunkingTests) — a pure static helper, tested
//     directly with no clock.
//   • dropping data points older than the service's 2-hour staleness window
//     (OCIMetricsExporterStalenessTests) — also a pure static helper, so the
//     boundary can be tested exactly without sleeping or an injected clock.
//   • end-to-end flush() behaviour against an injected MonitoringClient
//     transport (OCIMetricsExporterFlushTests): clean publishes, chunking on
//     the wire, failedMetrics arriving inside a 200, and a transport failure
//     that buffers a stream for retry — calling the exporter actor directly,
//     deterministically, with no sleeping.
// No ~/.oci/config, no network.
//

import Foundation
import Testing

@testable import OCIKit

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

// MARK: - Chunking (test group 2)

struct OCIMetricsExporterChunkingTests {
  private static let compartmentId = "ocid1.compartment.oc1..EXAMPLE"

  private func metric(_ name: String) -> MetricDataDetails {
    MetricDataDetails(
      namespace: "ocikit_probe",
      compartmentId: Self.compartmentId,
      name: name,
      dimensions: ["stream": name],
      datapoints: [MonitoringDatapoint(timestamp: Date(timeIntervalSince1970: 0), value: 1)]
    )
  }

  @Test("chunked(_:maximumStreamsPerRequest:) returns no requests for an empty snapshot")
  func chunkedEmptyReturnsNoRequests() {
    #expect(OCIMetricsExporter.chunked([], maximumStreamsPerRequest: 50).isEmpty)
  }

  @Test("chunked(_:maximumStreamsPerRequest:) returns a single request when under the limit")
  func chunkedUnderLimitIsOneRequest() {
    let metrics = (0..<10).map { metric("m\($0)") }
    let chunks = OCIMetricsExporter.chunked(metrics, maximumStreamsPerRequest: 50)
    #expect(chunks.count == 1)
    #expect(chunks.first?.count == 10)
  }

  @Test("chunked(_:maximumStreamsPerRequest:) returns a single request when exactly at the limit")
  func chunkedExactlyAtLimitIsOneRequest() {
    let metrics = (0..<50).map { metric("m\($0)") }
    let chunks = OCIMetricsExporter.chunked(metrics, maximumStreamsPerRequest: 50)
    #expect(chunks.count == 1)
    #expect(chunks.first?.count == 50)
  }

  @Test("chunked(_:maximumStreamsPerRequest:) splits 67 streams into 50 + 17, matching the service's 50-stream limit")
  func chunkedOverLimitSplitsCorrectly() {
    let metrics = (0..<67).map { metric("m\($0)") }
    let chunks = OCIMetricsExporter.chunked(metrics, maximumStreamsPerRequest: 50)
    #expect(chunks.map(\.count) == [50, 17])
    #expect(chunks.flatMap { $0 }.count == 67)
  }

  @Test("chunked(_:maximumStreamsPerRequest:) preserves input order across chunk boundaries")
  func chunkedPreservesOrder() {
    let metrics = (0..<67).map { metric("m\($0)") }
    let chunks = OCIMetricsExporter.chunked(metrics, maximumStreamsPerRequest: 50)
    #expect(chunks.flatMap { $0 }.map(\.name) == metrics.map(\.name))
  }

  @Test("chunked(_:maximumStreamsPerRequest:) does not split when the limit itself is non-positive")
  func chunkedNonPositiveLimitDoesNotSplit() {
    let metrics = (0..<67).map { metric("m\($0)") }
    let chunks = OCIMetricsExporter.chunked(metrics, maximumStreamsPerRequest: 0)
    #expect(chunks.count == 1)
    #expect(chunks.first?.count == 67)
  }
}

// MARK: - Staleness (test group 4)

struct OCIMetricsExporterStalenessTests {
  private static let compartmentId = "ocid1.compartment.oc1..EXAMPLE"
  private static let now = Date(timeIntervalSince1970: 1_700_000_000)
  // The pruning cutoff is `now - maximumDatapointAge` (2 hours), strictly.
  private static let cutoff = now.addingTimeInterval(-OCIMetricsExporter.maximumDatapointAge)

  private func metric(_ name: String, points: [MonitoringDatapoint]) -> MetricDataDetails {
    MetricDataDetails(
      namespace: "ocikit_probe",
      compartmentId: Self.compartmentId,
      name: name,
      dimensions: ["stream": name],
      metadata: ["unit": "ns"],
      datapoints: points
    )
  }

  @Test("pruningStaleDatapoints keeps a metric whose data points are all fresh, unchanged")
  func keepsFullyFreshMetricUnchanged() {
    let fresh = MonitoringDatapoint(timestamp: Self.now, value: 1)
    let result = OCIMetricsExporter.pruningStaleDatapoints([metric("m", points: [fresh])], now: Self.now)
    #expect(result.droppedDatapoints == 0)
    #expect(result.metrics.count == 1)
    #expect(result.metrics.first?.datapoints.count == 1)
  }

  @Test("pruningStaleDatapoints drops only the stale data points of a metric, keeping the fresh ones and the metric's other fields")
  func dropsOnlyStalePoints() throws {
    let stale = MonitoringDatapoint(timestamp: Self.cutoff.addingTimeInterval(-1), value: 999)
    let freshA = MonitoringDatapoint(timestamp: Self.now, value: 1)
    let freshB = MonitoringDatapoint(timestamp: Self.now, value: 2)
    let input = metric("m", points: [stale, freshA, freshB])

    let result = OCIMetricsExporter.pruningStaleDatapoints([input], now: Self.now)

    #expect(result.droppedDatapoints == 1)
    let kept = try #require(result.metrics.first)
    #expect(kept.datapoints.map(\.value) == [1, 2])
    #expect(kept.namespace == input.namespace)
    #expect(kept.name == input.name)
    #expect(kept.dimensions == input.dimensions)
    #expect(kept.metadata == input.metadata)
    #expect(kept.compartmentId == input.compartmentId)
  }

  @Test("pruningStaleDatapoints drops a metric entirely once every one of its data points is stale")
  func dropsMetricEntirelyWhenFullyStale() {
    let stale = MonitoringDatapoint(timestamp: Self.cutoff.addingTimeInterval(-1), value: 1)
    let result = OCIMetricsExporter.pruningStaleDatapoints([metric("m", points: [stale])], now: Self.now)
    #expect(result.metrics.isEmpty)
    #expect(result.droppedDatapoints == 1)
  }

  @Test("a data point exactly at the 2-hour cutoff is treated as stale (strict >, not >=)")
  func exactlyAtCutoffIsStale() {
    let atCutoff = MonitoringDatapoint(timestamp: Self.cutoff, value: 1)
    let result = OCIMetricsExporter.pruningStaleDatapoints([metric("m", points: [atCutoff])], now: Self.now)
    #expect(result.metrics.isEmpty)
    #expect(result.droppedDatapoints == 1)
  }

  @Test("a data point one second inside the cutoff is kept")
  func oneSecondInsideCutoffIsKept() {
    let justFresh = MonitoringDatapoint(timestamp: Self.cutoff.addingTimeInterval(1), value: 1)
    let result = OCIMetricsExporter.pruningStaleDatapoints([metric("m", points: [justFresh])], now: Self.now)
    #expect(result.metrics.count == 1)
    #expect(result.droppedDatapoints == 0)
  }

  @Test("pruningStaleDatapoints leaves an unaffected sibling metric untouched")
  func leavesSiblingMetricUntouched() {
    let stale = metric("stale_one", points: [MonitoringDatapoint(timestamp: Self.cutoff.addingTimeInterval(-1), value: 1)])
    let healthy = metric("healthy_one", points: [MonitoringDatapoint(timestamp: Self.now, value: 2)])

    let result = OCIMetricsExporter.pruningStaleDatapoints([stale, healthy], now: Self.now)

    #expect(result.metrics.map(\.name) == ["healthy_one"])
    #expect(result.droppedDatapoints == 1)
  }

  @Test("pruningStaleDatapoints of an empty input drops nothing")
  func emptyInputDropsNothing() {
    let result = OCIMetricsExporter.pruningStaleDatapoints([], now: Self.now)
    #expect(result.metrics.isEmpty)
    #expect(result.droppedDatapoints == 0)
  }
}

// MARK: - Flush integration (test groups 2 and 5, via the actor directly)

/// A scripted transport: replays canned responses/errors in order and records every
/// request body it was handed, so a test can assert on exactly what was posted and
/// exactly how many requests it took — deterministic, no live network.
private actor ScriptedTransport {
  enum Step: Sendable {
    case success(status: Int, body: Data)
    case failure(any Error & Sendable)
  }

  private var steps: [Step]
  private(set) var requestBodies: [Data] = []

  init(steps: [Step]) { self.steps = steps }

  func handle(_ request: URLRequest) throws -> (Data, URLResponse) {
    requestBodies.append(request.httpBody ?? Data())
    guard !steps.isEmpty else {
      return (Data(#"{"failedMetricsCount":0}"#.utf8), Self.response(for: request, status: 200))
    }
    switch steps.removeFirst() {
    case .success(let status, let body):
      return (body, Self.response(for: request, status: status))
    case .failure(let error):
      throw error
    }
  }

  private static func response(for request: URLRequest, status: Int) -> HTTPURLResponse {
    HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: [:])!
  }
}

/// A transport that holds its **first** request open until the test releases it, so a second flush
/// can be issued while the first is provably still on the wire. No sleeping, no polling.
private actor GatedTransport {
  private(set) var requestBodies: [Data] = []
  private var hasArrived = false
  private var isReleased = false
  private var arrival: CheckedContinuation<Void, Never>?
  private var release: CheckedContinuation<Void, Never>?

  func handle(_ request: URLRequest) async throws -> (Data, URLResponse) {
    let isFirst = requestBodies.isEmpty
    requestBodies.append(request.httpBody ?? Data())
    if isFirst {
      hasArrived = true
      arrival?.resume()
      arrival = nil
      if !isReleased {
        await withCheckedContinuation { self.release = $0 }
      }
    }
    let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:])!
    return (Data(#"{"failedMetricsCount":0}"#.utf8), response)
  }

  /// Returns once the first request has reached the transport — i.e. once the first flush has
  /// definitely drained the registry.
  func waitForFirstRequest() async {
    guard !hasArrived else { return }
    await withCheckedContinuation { self.arrival = $0 }
  }

  /// Lets the held first request complete.
  func releaseFirstRequest() {
    isReleased = true
    release?.resume()
    release = nil
  }
}

private struct TransportFailure: Error, Sendable {}

private struct NoopSigner: Signer {
  func sign(_ req: inout URLRequest) throws {}
}

// MARK: - Retry classification

struct OCIMetricsExporterRetryClassificationTests {
  @Test("a transport error is retryable — the identical payload may well succeed on the next step")
  func transportErrorIsRetryable() {
    #expect(OCIMetricsExporter.isRetryable(TransportFailure()))
    #expect(OCIMetricsExporter.isRetryable(URLError(.timedOut)))
  }

  @Test(
    "a 4xx other than 408/429 is permanent, a 408/429/5xx is not",
    arguments: [
      (400, false),  // every metric object failed input validation — re-posting it cannot help
      (401, false),
      (403, false),  // missing `use metrics` policy
      (404, false),
      (408, true),
      (429, true),  // throttling: the tenancy's 50 TPS budget, retry next step
      (500, true),
      (503, true),
    ]
  )
  func statusCodeClassification(status: Int, expected: Bool) {
    #expect(OCIMetricsExporter.isRetryable(MonitoringError.unexpectedStatusCode(status, "")) == expected)
  }

  @Test("a client-side encoding failure is permanent — the payload itself is unrepresentable")
  func encodingFailureIsPermanent() {
    #expect(OCIMetricsExporter.isRetryable(MonitoringError.jsonEncodingError("Unable to encode Double.nan")) == false)
  }
}

struct OCIMetricsExporterFlushTests {
  private static let compartmentId = "ocid1.compartment.oc1..EXAMPLE"

  private func makeConfiguration(
    commonDimensions: [String: String] = [:],
    defaultDimensionName: String = OCIMetricsConfiguration.fallbackDimensionName,
    defaultDimensionValue: String = "test-host",
    maximumBufferedStreams: Int = 500
  ) throws -> OCIMetricsConfiguration {
    try OCIMetricsConfiguration(
      namespace: "ocikit_probe",
      compartmentId: Self.compartmentId,
      commonDimensions: commonDimensions,
      defaultDimensionName: defaultDimensionName,
      defaultDimensionValue: defaultDimensionValue,
      maximumBufferedStreams: maximumBufferedStreams
    )
  }

  private func makeExporter(
    configuration: OCIMetricsConfiguration,
    registry: OCIMetricsRegistry,
    transport: ScriptedTransport
  ) throws -> OCIMetricsExporter {
    let http = HTTPClient { request in try await transport.handle(request) }
    let client = try MonitoringClient(region: .phx, signer: NoopSigner(), httpClient: http)
    return OCIMetricsExporter(client: client, configuration: configuration, registry: registry, logger: logger)
  }

  private func makeExporter(
    configuration: OCIMetricsConfiguration,
    registry: OCIMetricsRegistry,
    transport: GatedTransport
  ) throws -> OCIMetricsExporter {
    let http = HTTPClient { request in try await transport.handle(request) }
    let client = try MonitoringClient(region: .phx, signer: NoopSigner(), httpClient: http)
    return OCIMetricsExporter(client: client, configuration: configuration, registry: registry, logger: logger)
  }

  private func requestStreamCount(_ body: Data) throws -> Int {
    let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    let metricData = try #require(json["metricData"] as? [[String: Any]])
    return metricData.count
  }

  @Test("flush() with an idle registry posts no request and leaves statistics untouched")
  func flushWithIdleRegistryPostsNothing() async throws {
    let configuration = try makeConfiguration()
    let registry = OCIMetricsRegistry(configuration: configuration)
    let transport = ScriptedTransport(steps: [])
    let exporter = try makeExporter(configuration: configuration, registry: registry, transport: transport)

    await exporter.flush()

    #expect(await transport.requestBodies.isEmpty)
    #expect(await exporter.statistics() == OCIMetricsStatistics())
  }

  @Test("flush() of a large registry snapshot splits the wire request at 50 streams and accounts every one as posted")
  func flushChunksLargeSnapshotOnTheWire() async throws {
    let configuration = try makeConfiguration()
    let registry = OCIMetricsRegistry(configuration: configuration)
    for i in 0..<67 {
      registry.counter(id: OCIMetricsStreamID(kind: .counter, label: "metric_\(i)", dimensions: [:])).increment(by: 1)
    }
    let transport = ScriptedTransport(steps: [
      .success(status: 200, body: Data(#"{"failedMetricsCount":0}"#.utf8)),
      .success(status: 200, body: Data(#"{"failedMetricsCount":0}"#.utf8)),
    ])
    let exporter = try makeExporter(configuration: configuration, registry: registry, transport: transport)

    await exporter.flush()

    let bodies = await transport.requestBodies
    #expect(bodies.count == 2)
    #expect(try requestStreamCount(bodies[0]) == 50)
    #expect(try requestStreamCount(bodies[1]) == 17)

    let statistics = await exporter.statistics()
    #expect(statistics.postedStreams == 67)
    #expect(statistics.postedDatapoints == 67)
    #expect(statistics.failedRequests == 0)
  }

  @Test("flush() surfaces failedMetrics arriving inside a 200 without retrying the rejected stream")
  func flushSurfacesFailedMetricsInsideTwoHundredWithoutRetrying() async throws {
    let configuration = try makeConfiguration()
    let registry = OCIMetricsRegistry(configuration: configuration)
    registry.counter(id: OCIMetricsStreamID(kind: .counter, label: "probe_bad", dimensions: [:])).increment(by: 2)

    let rejectedBody = Data(
      #"""
      {"failedMetricsCount":1,"failedMetrics":[{"message":"The datapoint timestamps must be between 2 hours ago and 10 minutes from now.","metricData":{"compartmentId":"ocid1.compartment.oc1..EXAMPLE","datapoints":[{"count":null,"timestamp":"2020-01-01T00:00:00.000Z","value":2.0}],"dimensions":{"source":"test-host"},"metadata":null,"name":"probe_bad","namespace":"ocikit_probe","resourceGroup":null}}]}
      """#.utf8
    )
    let transport = ScriptedTransport(steps: [.success(status: 200, body: rejectedBody)])
    let exporter = try makeExporter(configuration: configuration, registry: registry, transport: transport)

    await exporter.flush()
    #expect(await transport.requestBodies.count == 1)

    var statistics = await exporter.statistics()
    #expect(statistics.failedMetrics == 1)
    #expect(statistics.postedStreams == 0)
    #expect(statistics.failedRequests == 0)

    // A rejection is permanent input-validation feedback, not a transport failure — the
    // stream must NOT be retried. The registry has nothing new to report, so a second
    // flush must not talk to the network at all.
    await exporter.flush()
    #expect(await transport.requestBodies.count == 1)
    statistics = await exporter.statistics()
    #expect(statistics.failedMetrics == 1)  // unchanged
  }

  @Test("flush() buffers a stream after a transport failure and successfully re-posts it on the next flush")
  func flushRetriesAfterTransportFailure() async throws {
    let configuration = try makeConfiguration()
    let registry = OCIMetricsRegistry(configuration: configuration)
    registry.counter(id: OCIMetricsStreamID(kind: .counter, label: "requests", dimensions: [:])).increment(by: 3)

    let transport = ScriptedTransport(steps: [
      .failure(TransportFailure()),
      .success(status: 200, body: Data(#"{"failedMetricsCount":0}"#.utf8)),
    ])
    let exporter = try makeExporter(configuration: configuration, registry: registry, transport: transport)

    await exporter.flush()
    var statistics = await exporter.statistics()
    #expect(statistics.failedRequests == 1)
    #expect(statistics.postedStreams == 0)

    // Nothing new was recorded, but the failed stream is still buffered and gets retried.
    await exporter.flush()
    #expect(await transport.requestBodies.count == 2)
    statistics = await exporter.statistics()
    #expect(statistics.failedRequests == 1)  // unchanged: the retry succeeded
    #expect(statistics.postedStreams == 1)
    #expect(statistics.postedDatapoints == 1)
  }

  @Test("flush() synthesizes the default dimension for a label-less counter and sanitizes malformed dimensions on the wire")
  func flushSynthesizesDefaultDimensionAndSanitizes() async throws {
    let configuration = try makeConfiguration(defaultDimensionName: "src", defaultDimensionValue: "unit-test-host")
    let registry = OCIMetricsRegistry(configuration: configuration)
    registry.counter(id: OCIMetricsStreamID(kind: .counter, label: "no_dims", dimensions: [:])).increment(by: 1)

    let overlongValue = String(repeating: "v", count: 600)
    registry.counter(id: OCIMetricsStreamID(kind: .counter, label: "messy_dims", dimensions: ["  bad key  ": overlongValue]))
      .increment(by: 1)

    let transport = ScriptedTransport(steps: [.success(status: 200, body: Data(#"{"failedMetricsCount":0}"#.utf8))])
    let exporter = try makeExporter(configuration: configuration, registry: registry, transport: transport)

    await exporter.flush()

    let body = try #require(await transport.requestBodies.first)
    let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    let metricData = try #require(json["metricData"] as? [[String: Any]])
    let byName = Dictionary(uniqueKeysWithValues: metricData.map { ($0["name"] as? String ?? "", $0) })

    let noDims = try #require(byName["no_dims"])
    #expect(noDims["dimensions"] as? [String: String] == ["src": "unit-test-host"])

    let messy = try #require(byName["messy_dims"])
    let messyDimensions = try #require(messy["dimensions"] as? [String: String])
    #expect(messyDimensions["bad_key"] == String(repeating: "v", count: 512))
  }

  @Test("flush() attaches unit metadata only for timer streams")
  func flushAttachesTimerMetadataOnly() async throws {
    let configuration = try makeConfiguration()
    let registry = OCIMetricsRegistry(configuration: configuration)
    registry.timer(id: OCIMetricsStreamID(kind: .timer, label: "latency", dimensions: [:])).recordNanoseconds(1_500_000)

    let transport = ScriptedTransport(steps: [.success(status: 200, body: Data(#"{"failedMetricsCount":0}"#.utf8))])
    let exporter = try makeExporter(configuration: configuration, registry: registry, transport: transport)

    await exporter.flush()

    let body = try #require(await transport.requestBodies.first)
    let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    let metricData = try #require(json["metricData"] as? [[String: Any]])
    let metric = try #require(metricData.first)
    #expect(metric["metadata"] as? [String: String] == ["unit": "ns"])
  }

  @Test("a healthy flush with more live streams than maximumBufferedStreams drops nothing: the bound is on the retry buffer")
  func flushDoesNotApplyRetryBoundToFreshStreams() async throws {
    // The registry holds 6 live streams and the bound is 3. Nothing has failed, so nothing belongs
    // in the retry buffer and nothing may be dropped — otherwise the same lexicographically-first
    // streams would be discarded on every single step, forever.
    let configuration = try makeConfiguration(maximumBufferedStreams: 3)
    let registry = OCIMetricsRegistry(configuration: configuration)
    for i in 0..<6 {
      registry.counter(id: OCIMetricsStreamID(kind: .counter, label: "metric_\(i)", dimensions: [:])).increment(by: 1)
    }
    let transport = ScriptedTransport(steps: [.success(status: 200, body: Data(#"{"failedMetricsCount":0}"#.utf8))])
    let exporter = try makeExporter(configuration: configuration, registry: registry, transport: transport)

    await exporter.flush()

    let statistics = await exporter.statistics()
    #expect(statistics.droppedBufferedStreams == 0)
    #expect(statistics.postedStreams == 6)
    let body = try #require(await transport.requestBodies.first)
    #expect(try requestStreamCount(body) == 6)
  }

  @Test("maximumBufferedStreams bounds the retry buffer after a transport failure, dropping the oldest")
  func retryBufferIsBoundedAfterTransportFailure() async throws {
    let configuration = try makeConfiguration(maximumBufferedStreams: 3)
    let registry = OCIMetricsRegistry(configuration: configuration)
    for i in 0..<6 {
      registry.counter(id: OCIMetricsStreamID(kind: .counter, label: "metric_\(i)", dimensions: [:])).increment(by: 1)
    }
    let transport = ScriptedTransport(steps: [
      .failure(TransportFailure()),
      .success(status: 200, body: Data(#"{"failedMetricsCount":0}"#.utf8)),
    ])
    let exporter = try makeExporter(configuration: configuration, registry: registry, transport: transport)

    await exporter.flush()
    #expect(await exporter.statistics().droppedBufferedStreams == 3)

    // Only the 3 that fit in the buffer are retried, and the registry drained ascending by stream
    // sort key, so it is the 3 most recent that survive.
    await exporter.flush()
    let bodies = await transport.requestBodies
    #expect(bodies.count == 2)
    #expect(try requestStreamCount(bodies[1]) == 3)
    #expect(await exporter.statistics().postedStreams == 3)
  }

  @Test("a 400 rejecting the whole batch is dropped, not re-posted forever")
  func flushDropsPermanentlyRejectedChunk() async throws {
    let configuration = try makeConfiguration()
    let registry = OCIMetricsRegistry(configuration: configuration)
    registry.counter(id: OCIMetricsStreamID(kind: .counter, label: "requests", dimensions: [:])).increment(by: 1)

    let errorBody = Data(#"{"code":"InvalidParameter","message":"namespace must match pattern"}"#.utf8)
    let transport = ScriptedTransport(steps: [.success(status: 400, body: errorBody)])
    let exporter = try makeExporter(configuration: configuration, registry: registry, transport: transport)

    await exporter.flush()
    var statistics = await exporter.statistics()
    #expect(statistics.failedRequests == 1)
    #expect(statistics.failedMetrics == 1)
    #expect(statistics.postedStreams == 0)

    // Nothing was buffered: the identical payload would be rejected identically.
    await exporter.flush()
    #expect(await transport.requestBodies.count == 1)
    statistics = await exporter.statistics()
    #expect(statistics.failedRequests == 1)
    #expect(statistics.failedMetrics == 1)
  }

  @Test("a 429 is transient: the chunk is buffered and re-posted on the next flush")
  func flushRetriesThrottledChunk() async throws {
    let configuration = try makeConfiguration()
    let registry = OCIMetricsRegistry(configuration: configuration)
    registry.counter(id: OCIMetricsStreamID(kind: .counter, label: "requests", dimensions: [:])).increment(by: 1)

    let transport = ScriptedTransport(steps: [
      .success(status: 429, body: Data(#"{"code":"TooManyRequests","message":"throttled"}"#.utf8)),
      .success(status: 200, body: Data(#"{"failedMetricsCount":0}"#.utf8)),
    ])
    let exporter = try makeExporter(configuration: configuration, registry: registry, transport: transport)

    await exporter.flush()
    #expect(await exporter.statistics().failedRequests == 1)

    await exporter.flush()
    #expect(await transport.requestBodies.count == 2)
    let statistics = await exporter.statistics()
    #expect(statistics.postedStreams == 1)
    #expect(statistics.failedMetrics == 0)
  }

  @Test("flush() that races an in-flight flush publishes what was recorded after that flush drained")
  func flushRacingAnInFlightFlushStillPublishesRecentData() async throws {
    let configuration = try makeConfiguration()
    let registry = OCIMetricsRegistry(configuration: configuration)
    registry.counter(id: OCIMetricsStreamID(kind: .counter, label: "first", dimensions: [:])).increment(by: 1)

    let transport = GatedTransport()
    let exporter = try makeExporter(configuration: configuration, registry: registry, transport: transport)

    let first = Task { await exporter.flush() }
    await transport.waitForFirstRequest()  // the first flush has drained and is on the wire

    // Recorded strictly after that drain, so only a *second* snapshot can carry it.
    registry.counter(id: OCIMetricsStreamID(kind: .counter, label: "second", dimensions: [:])).increment(by: 5)
    let second = Task { await exporter.flush() }

    await transport.releaseFirstRequest()
    await first.value
    await second.value

    let bodies = await transport.requestBodies
    #expect(bodies.count == 2)
    let json = try #require(try JSONSerialization.jsonObject(with: bodies[1]) as? [String: Any])
    let metricData = try #require(json["metricData"] as? [[String: Any]])
    #expect(metricData.map { $0["name"] as? String } == ["second"])
    #expect(await exporter.statistics().postedStreams == 2)
  }

  @Test("statistics() starts at all zeros before any flush has run")
  func statisticsStartsAtZero() async throws {
    let configuration = try makeConfiguration()
    let registry = OCIMetricsRegistry(configuration: configuration)
    let exporter = try makeExporter(configuration: configuration, registry: registry, transport: ScriptedTransport(steps: []))
    #expect(await exporter.statistics() == OCIMetricsStatistics())
  }
}
