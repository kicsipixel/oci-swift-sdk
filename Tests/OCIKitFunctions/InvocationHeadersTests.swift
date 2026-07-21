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
import NIOCore
import NIOHTTP1
import NIOPosix
import Testing

@testable import OCIKitFunctions

/// End-to-end tests over a real ``FunctionServer`` Unix-socket connection (same
/// harness shape as `FunctionServerTests`) covering issue #86: raw invocation
/// headers — most importantly the Zipkin `X-B3-*` tracing headers — must reach
/// ``InvocationContext/invocationHeaders`` on **every** invocation, including
/// plain (non-HTTP-gateway) ones, while the existing ``InvocationContext/httpHeaders``
/// decapsulation behavior for HTTP-gateway invocations is unchanged.
@Suite("Invocation headers + tracing context, end to end")
struct InvocationHeadersTests {

  @Test("a plain invoke exposes X-B3-* headers via invocationHeaders even though httpHeaders stays empty")
  func plainInvokeSurfacesRawHeaders() async throws {
    try await withRunningServer(
      handler: { context, _ in
        #expect(!context.isHTTPRequest)
        // The bug: httpHeaders is HTTP-gateway-only by contract and must stay empty.
        #expect(context.httpHeaders.count == 0)
        // The fix: the raw pairs — Fn-* contract headers and X-B3-* alike — survive.
        #expect(context.invocationHeaders.first("X-B3-TraceId") == "463ac35c9f6413ad48485a3953bb6124")
        #expect(context.invocationHeaders.first("X-B3-SpanId") == "a2fb4a1d1a96d312")
        #expect(context.invocationHeaders.first("Fn-Call-Id") == "call-plain")
        // And the typed view built from those raw headers agrees.
        #expect(context.tracing.traceId == "463ac35c9f6413ad48485a3953bb6124")
        #expect(context.tracing.spanId == "a2fb4a1d1a96d312")
        #expect(context.tracing.parentSpanId == nil)
        #expect(context.tracing.isSampled)  // absent on a direct invoke -> sampled
        return FunctionResponse.text("ok")
      }
    ) { socketPath in
      let result = try await sendInvocation(
        to: socketPath,
        headers: [
          ("Fn-Call-Id", "call-plain"),
          ("X-B3-TraceId", "463ac35c9f6413ad48485a3953bb6124"),
          ("X-B3-SpanId", "a2fb4a1d1a96d312"),
        ],
        body: Data()
      )
      #expect(result.status == 200)
    }
  }

  @Test(
    "an HTTP-gateway invoke keeps httpHeaders decapsulated exactly as before, and also exposes the still-prefixed originals plus X-B3-* via invocationHeaders"
  )
  func httpInvokeKeepsDecapsulationAndSurfacesRawHeaders() async throws {
    try await withRunningServer(
      handler: { context, _ in
        #expect(context.isHTTPRequest)
        // Unchanged decapsulation semantics: prefix stripped, Fn-* not leaked.
        #expect(context.httpHeaders["X-Client"] == "abc")
        #expect(context.httpHeaders["Fn-Http-H-X-Client"] == nil)
        #expect(context.httpHeaders["Fn-Call-Id"] == nil)
        // New: the raw pairs are still there, prefix and all, alongside X-B3-*.
        #expect(context.invocationHeaders.first("Fn-Http-H-X-Client") == "abc")
        #expect(context.invocationHeaders.first("X-Client") == nil)
        #expect(context.invocationHeaders.first("X-B3-TraceId") == "1a2b3c4d5e6f7081")
        #expect(context.tracing.traceId == "1a2b3c4d5e6f7081")
        return FunctionResponse.text("ok")
      }
    ) { socketPath in
      let result = try await sendInvocation(
        to: socketPath,
        headers: [
          ("Fn-Call-Id", "call-http"),
          ("Fn-Intent", "httprequest"),
          ("Fn-Http-Method", "GET"),
          ("Fn-Http-Request-Url", "/orders/1"),
          ("Fn-Http-H-X-Client", "abc"),
          ("X-B3-TraceId", "1a2b3c4d5e6f7081"),
        ],
        body: Data()
      )
      #expect(result.status == 200)
    }
  }

  @Test("OCI_TRACING_ENABLED / OCI_TRACE_COLLECTOR_URL configured on the runtime surface through context.tracing")
  func runtimeTracingConfigurationSurfaces() async throws {
    let collectorURL =
      "https://EXAMPLE.apm-agt.us-phoenix-1.oci.oraclecloud.com/20200101/observations/public-span"
      + "?dataFormat=zipkin&dataFormatVersion=2&dataKey=exampleDataKey"
    try await withRunningServer(
      config: [
        "FN_APP_ID": "ocid1.app.oc1..aaaa",
        "FN_FN_ID": "ocid1.fnfunc.oc1..bbbb",
        "FN_APP_NAME": "MyApp",
        "FN_FN_NAME": "MyFunction",
        "OCI_TRACING_ENABLED": "1",
        "OCI_TRACE_COLLECTOR_URL": collectorURL,
      ],
      handler: { context, _ in
        let tracing = context.tracing
        #expect(tracing.isEnabled)
        #expect(tracing.serviceName == "myapp::myfunction")
        #expect(tracing.traceCollectorURL == collectorURL)
        let endpoint = try #require(tracing.collectorEndpoint)
        #expect(endpoint.visibility == .publicSpan)
        #expect(endpoint.dataKey == "exampleDataKey")
        return FunctionResponse.text("ok")
      }
    ) { socketPath in
      let result = try await sendInvocation(to: socketPath, headers: [("Fn-Call-Id", "call-cfg")], body: Data())
      #expect(result.status == 200)
    }
  }

  // MARK: - Harness (mirrors FunctionServerTests' private harness)

  private func withRunningServer(
    config: [String: String] = ["FN_APP_ID": "ocid1.app.oc1..aaaa", "FN_FN_ID": "ocid1.fnfunc.oc1..bbbb"],
    handler: @escaping FunctionHandler,
    _ body: @Sendable (_ socketPath: String) async throws -> Void
  ) async throws {
    let shortID = String(UUID().uuidString.prefix(8))
    let dir = URL(fileURLWithPath: "/tmp/fdk-\(shortID)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let socketPath = dir.appendingPathComponent("lsnr.sock").path
    let listener = FnListener(socketPath: socketPath)
    let runtime = RuntimeContext(config: config)
    let server = FunctionServer(
      listener: listener,
      runtime: runtime,
      handler: handler,
      logger: Logger(label: "InvocationHeadersTests")
    )

    let box = ServerErrorBox()
    let serverTask = Task {
      do { try await server.run() }
      catch { await box.set(error) }
    }
    defer { serverTask.cancel() }

    try await waitForSocket(at: socketPath, box: box)
    try await body(socketPath)
  }

  private func waitForSocket(at path: String, box: ServerErrorBox) async throws {
    for _ in 0..<100 {
      if let error = await box.error {
        Issue.record("Function server failed to start: \(error)")
        return
      }
      if FileManager.default.fileExists(atPath: path) { return }
      try await Task.sleep(for: .milliseconds(50))
    }
    Issue.record("Function socket never became ready at \(path)")
  }

  private func sendInvocation(
    to socketPath: String,
    headers: [(String, String)],
    body: Data
  ) async throws -> (status: Int, headers: [(name: String, value: String)], body: Data) {
    let group = MultiThreadedEventLoopGroup.singleton
    let channel = try await ClientBootstrap(group: group)
      .connect(unixDomainSocketPath: socketPath) { channel in
        channel.eventLoop.makeCompletedFuture {
          try channel.pipeline.syncOperations.addHTTPClientHandlers()
          return try NIOAsyncChannel<HTTPClientResponsePart, HTTPClientRequestPart>(
            wrappingChannelSynchronously: channel
          )
        }
      }
    return try await channel.executeThenClose { inbound, outbound in
      try await writeRequest(to: outbound, headers: headers, body: body)
      var iterator = inbound.makeAsyncIterator()
      return try await readResponse(&iterator)
    }
  }

  private func writeRequest(
    to outbound: NIOAsyncChannelOutboundWriter<HTTPClientRequestPart>,
    headers: [(String, String)],
    body: Data
  ) async throws {
    var head = HTTPRequestHead(version: .http1_1, method: .POST, uri: "/call")
    head.headers.add(name: "Host", value: "localhost")
    for (name, value) in headers {
      head.headers.add(name: name, value: value)
    }
    head.headers.add(name: "Content-Length", value: String(body.count))
    head.headers.add(name: "Connection", value: "close")
    try await outbound.write(.head(head))
    if !body.isEmpty {
      try await outbound.write(.body(.byteBuffer(ByteBuffer(bytes: body))))
    }
    try await outbound.write(.end(nil))
  }

  private func readResponse(
    _ iterator: inout NIOAsyncChannelInboundStream<HTTPClientResponsePart>.AsyncIterator
  ) async throws -> (status: Int, headers: [(name: String, value: String)], body: Data) {
    var status = 0
    var headers: [(name: String, value: String)] = []
    var body = Data()
    while let part = try await iterator.next() {
      switch part {
      case .head(let head):
        status = Int(head.status.code)
        headers = head.headers.map { (name: $0.name, value: $0.value) }
      case .body(let buffer):
        body.append(contentsOf: buffer.readableBytesView)
      case .end:
        return (status, headers, body)
      }
    }
    return (status, headers, body)
  }
}

/// Captures an error thrown by the background server task so tests can surface it.
private actor ServerErrorBox {
  private(set) var error: Error?
  func set(_ error: Error) { self.error = error }
}
