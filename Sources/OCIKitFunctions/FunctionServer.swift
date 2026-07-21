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

/// The Fn http-stream server: a persistent HTTP/1.1 server over a Unix domain
/// socket that turns each request into one invocation of the user's handler.
struct FunctionServer: Sendable {
  let listener: FnListener
  let runtime: RuntimeContext
  let handler: FunctionHandler
  let logger: Logger

  /// Signals that the handler did not finish before ``InvocationContext/deadline``.
  private struct DeadlineExceeded: Error {}

  // MARK: - Run loop

  /// Prepares the listener socket and serves invocations until the socket closes.
  func run() async throws {
    let real = listener.socketPath
    let phony = listener.phonyPath

    // Start from a clean slate: remove any stale sockets left by a previous run.
    removeIfPresent(real)
    removeIfPresent(phony)

    let group = MultiThreadedEventLoopGroup.singleton
    let serverChannel: NIOAsyncChannel<NIOAsyncChannel<HTTPServerRequestPart, HTTPServerResponsePart>, Never>
    do {
      serverChannel = try await ServerBootstrap(group: group)
        .serverChannelOption(ChannelOptions.backlog, value: 256)
        .bind(unixDomainSocketPath: phony, cleanupExistingSocketFile: true) { channel in
          channel.eventLoop.makeCompletedFuture {
            try channel.pipeline.syncOperations.configureHTTPServerPipeline(withErrorHandling: true)
            return try NIOAsyncChannel<HTTPServerRequestPart, HTTPServerResponsePart>(
              wrappingChannelSynchronously: channel
            )
          }
        }
    }
    catch {
      throw FunctionRuntimeError.socketSetupFailed("could not bind \(phony): \(error)")
    }

    // Readiness handshake: make the phony socket world-writable (the Fn agent
    // connects as a different uid), then atomically expose it at the real path via
    // a RELATIVE symlink. Order matters — the symlink is the platform's "ready"
    // signal, so it must appear only after the socket is bound and chmod'd.
    do {
      try FileManager.default.setAttributes([.posixPermissions: 0o666], ofItemAtPath: phony)
      try FileManager.default.createSymbolicLink(atPath: real, withDestinationPath: listener.symlinkTarget)
    }
    catch {
      throw FunctionRuntimeError.socketSetupFailed("could not expose \(real): \(error)")
    }

    logger.info("OCIKitFunctions serving on \(real) (bound at \(phony))")

    try await serverChannel.executeThenClose { inbound in
      try await withThrowingDiscardingTaskGroup { taskGroup in
        for try await connection in inbound {
          taskGroup.addTask {
            await handleConnection(connection)
          }
        }
      }
    }
  }

  // MARK: - Per-connection handling (HTTP/1.1 keep-alive)

  /// Serves every keep-alive request on a single connection, in order.
  private func handleConnection(
    _ channel: NIOAsyncChannel<HTTPServerRequestPart, HTTPServerResponsePart>
  ) async {
    do {
      try await channel.executeThenClose { inbound, outbound in
        var iterator = inbound.makeAsyncIterator()
        while true {
          // Read the request head (or stop when the peer closes the connection).
          guard let firstPart = try await iterator.next() else { return }
          guard case .head(let head) = firstPart else { return }

          // Drain the full body so the connection can be reused for the next request.
          var bodyBuffer = ByteBuffer()
          bodyLoop: while true {
            guard let part = try await iterator.next() else { return }
            switch part {
            case .head:
              return  // protocol violation: a new head before the previous end
            case .body(var chunk):
              bodyBuffer.writeBuffer(&chunk)
            case .end:
              break bodyLoop
            }
          }

          let body = Data(bodyBuffer.readableBytesView)
          let (socketStatus, headers, responseBody) = await dispatch(head: head, body: body)
          try await writeResponse(
            version: head.version,
            socketStatus: socketStatus,
            headers: headers,
            body: responseBody,
            keepAlive: head.isKeepAlive,
            to: outbound
          )
          if !head.isKeepAlive { return }
        }
      }
    }
    catch {
      logger.debug("Connection closed with error: \(error)")
    }
  }

  // MARK: - Invocation dispatch

  /// Turns one request into an invocation and returns the socket status, response
  /// headers (minus Content-Length), and response body.
  private func dispatch(
    head: HTTPRequestHead,
    body: Data
  ) async -> (socketStatus: Int, headers: [(name: String, value: String)], body: Data) {
    let now = Date()
    let intentValue = head.headers.first(name: FnHeader.intent)
    let isHTTP = FnContract.isHTTPRequest(intentValue: intentValue)
    let callID = head.headers.first(name: FnHeader.callID)
    let deadline = FnContract.parseDeadline(head.headers.first(name: FnHeader.deadline), now: now)

    let pairs = head.headers.map { (name: $0.name, value: $0.value) }
    let context = InvocationContext(
      runtime: runtime,
      callID: callID,
      deadline: deadline,
      isHTTPRequest: isHTTP,
      httpMethod: isHTTP ? head.headers.first(name: FnHeader.httpMethod) : nil,
      requestURL: isHTTP ? head.headers.first(name: FnHeader.httpRequestURL) : nil,
      httpHeaders: isHTTP ? FnContract.decapsulateRequestHeaders(pairs) : FunctionHeaders()
    )
    let request = FunctionRequest(body: body, contentType: head.headers.first(name: FnHeader.contentType))

    emitLogFrame(head: head)

    do {
      let response = try await runWithDeadline(deadline, now: now) {
        try await handler(context, request)
      }
      return (200, FnContract.encapsulateResponseHeaders(response, isHTTPRequest: isHTTP), response.body)
    }
    catch is DeadlineExceeded {
      logger.error("Invocation \(callID ?? "unknown") exceeded its deadline")
      let response = FunctionResponse.text("Function invocation timed out")
      return (504, FnContract.encapsulateResponseHeaders(response, isHTTPRequest: false), response.body)
    }
    catch {
      logger.error("Invocation \(callID ?? "unknown") failed: \(error)")
      let response = FunctionResponse.text("Function invocation failed")
      return (502, FnContract.encapsulateResponseHeaders(response, isHTTPRequest: false), response.body)
    }
  }

  /// Runs `operation`, throwing ``DeadlineExceeded`` if `deadline` passes first.
  ///
  /// Enforcement is cooperative: on deadline the handler task is cancelled, so a
  /// handler that performs `async` I/O (or checks `Task.isCancelled`) stops promptly
  /// and the `504` is written immediately. A handler that never suspends — a tight
  /// CPU loop or a blocking synchronous call — cannot be interrupted and will delay
  /// the `504` until it returns; the Fn platform independently enforces the hard
  /// deadline by reaping the container, so such a handler is bounded externally.
  private func runWithDeadline(
    _ deadline: Date,
    now: Date,
    _ operation: @escaping @Sendable () async throws -> FunctionResponse
  ) async throws -> FunctionResponse {
    let interval = deadline.timeIntervalSince(now)
    guard interval > 0 else { throw DeadlineExceeded() }
    return try await withThrowingTaskGroup(of: FunctionResponse.self) { taskGroup in
      taskGroup.addTask { try await operation() }
      taskGroup.addTask {
        try await Task.sleep(for: .seconds(interval))
        throw DeadlineExceeded()
      }
      defer { taskGroup.cancelAll() }
      guard let result = try await taskGroup.next() else { throw DeadlineExceeded() }
      return result
    }
  }

  // MARK: - Response writing

  private func writeResponse(
    version: HTTPVersion,
    socketStatus: Int,
    headers: [(name: String, value: String)],
    body: Data,
    keepAlive: Bool,
    to outbound: NIOAsyncChannelOutboundWriter<HTTPServerResponsePart>
  ) async throws {
    var responseHeaders = HTTPHeaders()
    for (name, value) in headers {
      responseHeaders.add(name: name, value: value)
    }
    responseHeaders.add(name: "Content-Length", value: String(body.count))
    if !keepAlive {
      responseHeaders.add(name: "Connection", value: "close")
    }
    let head = HTTPResponseHead(
      version: version,
      status: HTTPResponseStatus(statusCode: socketStatus),
      headers: responseHeaders
    )
    try await outbound.write(.head(head))
    if !body.isEmpty {
      try await outbound.write(.body(.byteBuffer(ByteBuffer(bytes: body))))
    }
    try await outbound.write(.end(nil))
  }

  // MARK: - Log framing

  /// Emits the per-invocation log-frame marker when `FN_LOGFRAME_NAME` /
  /// `FN_LOGFRAME_HDR` are configured, letting the platform de-interleave logs.
  ///
  /// This deliberately writes raw markers to stdout **and** stderr — it is a
  /// required Fn protocol signal, not a diagnostic (which always go through the logger).
  private func emitLogFrame(head: HTTPRequestHead) {
    guard
      let name = runtime.config["FN_LOGFRAME_NAME"], !name.isEmpty,
      let headerName = runtime.config["FN_LOGFRAME_HDR"], !headerName.isEmpty,
      let value = head.headers.first(name: headerName), !value.isEmpty
    else {
      return
    }
    let marker = Data("\n\(name)=\(value)\n".utf8)
    // Best-effort telemetry: a broken/closed stdout or stderr (e.g. during container
    // teardown) must never abort the runtime, so swallow write failures rather than
    // using the trapping FileHandle.write(_:) overload.
    try? FileHandle.standardOutput.write(contentsOf: marker)
    try? FileHandle.standardError.write(contentsOf: marker)
  }

  // MARK: - Helpers

  private func removeIfPresent(_ path: String) {
    try? FileManager.default.removeItem(atPath: path)
  }
}
