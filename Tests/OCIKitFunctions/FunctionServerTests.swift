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

/// End-to-end tests that run a real ``FunctionServer`` over a Unix domain socket
/// and drive it with an in-process HTTP/1.1 client. These are credential-free and
/// socket-only (no OCI, no network), so they exercise the full http-stream contract
/// — the phony-socket readiness dance, request decapsulation, response
/// encapsulation, keep-alive, and deadline/error status mapping.
@Suite("FDK server over a Unix socket")
struct FunctionServerTests {

  @Test("HTTP-triggered invocation decapsulates the request and encapsulates the response")
  func httpTriggeredRoundTrip() async throws {
    try await withRunningServer(
      handler: { context, request in
        #expect(context.isHTTPRequest)
        #expect(context.httpMethod == "PUT")
        #expect(context.requestURL == "/orders/42")
        #expect(context.httpHeaders["X-Client"] == "abc")
        #expect(request.string == "ping")
        var response = FunctionResponse.text("pong", status: 201)
        response.headers["X-Server"] = "xyz"
        return response
      }
    ) { socketPath in
      let result = try await sendInvocation(
        to: socketPath,
        headers: [
          ("Fn-Call-Id", "01ABCDEF"),
          ("Fn-Intent", "httprequest"),
          ("Fn-Http-Method", "PUT"),
          ("Fn-Http-Request-Url", "/orders/42"),
          ("Fn-Http-H-X-Client", "abc"),
          ("Content-Type", "text/plain"),
        ],
        body: Data("ping".utf8)
      )
      // Socket status stays 200; the user status rides in Fn-Http-Status.
      #expect(result.status == 200)
      #expect(header(result.headers, "Fn-Http-Status") == "201")
      #expect(header(result.headers, "Fn-Http-H-X-Server") == "xyz")
      #expect(header(result.headers, "Content-Type") == "text/plain; charset=utf-8")
      #expect(header(result.headers, "Fn-Fdk-Version") == FnFdk.version)
      #expect(String(data: result.body, encoding: .utf8) == "pong")
    }
  }

  @Test("plain invocation returns the raw body with no Fn-Http-* wrapping")
  func plainInvocation() async throws {
    try await withRunningServer(
      handler: { context, request in
        #expect(!context.isHTTPRequest)
        return FunctionResponse.data(request.body, contentType: "application/octet-stream")
      }
    ) { socketPath in
      let result = try await sendInvocation(
        to: socketPath,
        headers: [("Fn-Call-Id", "02XYZ"), ("Content-Type", "application/octet-stream")],
        body: Data([0x01, 0x02, 0x03])
      )
      #expect(result.status == 200)
      #expect(header(result.headers, "Fn-Http-Status") == nil)
      #expect(header(result.headers, "Content-Type") == "application/octet-stream")
      #expect(Array(result.body) == [0x01, 0x02, 0x03])
    }
  }

  @Test("two invocations are served on one keep-alive connection")
  func keepAliveReuse() async throws {
    try await withRunningServer(
      handler: { _, request in FunctionResponse.text("echo:\(request.string ?? "")") }
    ) { socketPath in
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
      try await channel.executeThenClose { inbound, outbound in
        var iterator = inbound.makeAsyncIterator()
        for n in 1...2 {
          try await writeRequest(
            to: outbound,
            headers: [("Fn-Call-Id", "call-\(n)")],
            body: Data("\(n)".utf8),
            keepAlive: true
          )
          let response = try await readResponse(&iterator)
          #expect(String(data: response.body, encoding: .utf8) == "echo:\(n)")
        }
      }
    }
  }

  @Test("a handler that overruns its deadline yields a 504")
  func deadlineExceeded() async throws {
    try await withRunningServer(
      handler: { _, _ in
        try await Task.sleep(for: .seconds(30))
        return FunctionResponse.text("should never return")
      }
    ) { socketPath in
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      let deadline = formatter.string(from: Date().addingTimeInterval(0.3))
      let result = try await sendInvocation(
        to: socketPath,
        headers: [("Fn-Call-Id", "slow"), ("Fn-Deadline", deadline)],
        body: Data()
      )
      #expect(result.status == 504)
    }
  }

  @Test("a handler that throws yields a 502")
  func handlerError() async throws {
    struct Boom: Error {}
    try await withRunningServer(
      handler: { _, _ in throw Boom() }
    ) { socketPath in
      let result = try await sendInvocation(
        to: socketPath,
        headers: [("Fn-Call-Id", "bad")],
        body: Data()
      )
      #expect(result.status == 502)
    }
  }

  // MARK: - Harness

  /// Runs `handler` in a ``FunctionServer`` bound to a fresh temp socket, waits for
  /// readiness, runs `body`, then tears the server down.
  private func withRunningServer(
    handler: @escaping FunctionHandler,
    _ body: @Sendable (_ socketPath: String) async throws -> Void
  ) async throws {
    // Bind under a short /tmp path: a Unix socket path must fit in sun_path
    // (~104 bytes on macOS), which the default temp directory blows past.
    let shortID = String(UUID().uuidString.prefix(8))
    let dir = URL(fileURLWithPath: "/tmp/fdk-\(shortID)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let socketPath = dir.appendingPathComponent("lsnr.sock").path
    let listener = FnListener(socketPath: socketPath)
    let runtime = RuntimeContext(config: ["FN_APP_ID": "ocid1.app.oc1..aaaa", "FN_FN_ID": "ocid1.fnfunc.oc1..bbbb"])
    let server = FunctionServer(
      listener: listener,
      runtime: runtime,
      handler: handler,
      logger: Logger(label: "FunctionServerTests")
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

  /// Polls until the listener symlink appears (readiness), up to ~5 seconds.
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

  /// Opens a fresh connection, sends one invocation, and returns the response.
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
      try await writeRequest(to: outbound, headers: headers, body: body, keepAlive: false)
      var iterator = inbound.makeAsyncIterator()
      return try await readResponse(&iterator)
    }
  }

  private func writeRequest(
    to outbound: NIOAsyncChannelOutboundWriter<HTTPClientRequestPart>,
    headers: [(String, String)],
    body: Data,
    keepAlive: Bool
  ) async throws {
    var head = HTTPRequestHead(version: .http1_1, method: .POST, uri: "/call")
    head.headers.add(name: "Host", value: "localhost")
    for (name, value) in headers {
      head.headers.add(name: name, value: value)
    }
    head.headers.add(name: "Content-Length", value: String(body.count))
    head.headers.add(name: "Connection", value: keepAlive ? "keep-alive" : "close")
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

  private func header(_ list: [(name: String, value: String)], _ name: String) -> String? {
    list.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
  }
}

/// Captures an error thrown by the background server task so tests can surface it.
private actor ServerErrorBox {
  private(set) var error: Error?
  func set(_ error: Error) { self.error = error }
}
