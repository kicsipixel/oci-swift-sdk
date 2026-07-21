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
import Testing

@testable import OCIKitFunctions

/// Credential-free, socket-free unit tests for the pure Fn http-stream contract
/// transforms (``FnContract``) and `FN_LISTENER` parsing (``FnListener``).
@Suite("Fn http-stream contract")
struct FnContractTests {

  @Test("parse strips the exact unix: prefix and derives the phony path + relative symlink target")
  func listenerParsing() throws {
    let listener = try FnListener.parse("unix:/tmp/iofs/lsnr.sock")
    #expect(listener.socketPath == "/tmp/iofs/lsnr.sock")
    #expect(listener.phonyPath == "/tmp/iofs/phonylsnr.sock")
    #expect(listener.symlinkTarget == "phonylsnr.sock")
  }

  @Test("parse rejects a non-unix scheme and an empty path")
  func listenerParsingRejects() {
    #expect(throws: FunctionRuntimeError.self) { try FnListener.parse("tcp:127.0.0.1:8080") }
    #expect(throws: FunctionRuntimeError.self) { try FnListener.parse("unix:") }
  }

  @Test("validateFormat accepts empty or http-stream and rejects anything else")
  func formatValidation() throws {
    try FnListener.validateFormat([:])
    try FnListener.validateFormat(["FN_FORMAT": "http-stream"])
    #expect(throws: FunctionRuntimeError.self) { try FnListener.validateFormat(["FN_FORMAT": "json"]) }
  }

  @Test("isHTTPRequest matches Fn-Intent httprequest case-insensitively")
  func intentGating() {
    #expect(FnContract.isHTTPRequest(intentValue: "httprequest"))
    #expect(FnContract.isHTTPRequest(intentValue: "HttpRequest"))
    #expect(!FnContract.isHTTPRequest(intentValue: "cloudevent"))
    #expect(!FnContract.isHTTPRequest(intentValue: nil))
  }

  @Test("parseDeadline reads RFC3339 and defaults to now+30s when absent")
  func deadlineParsing() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let parsed = FnContract.parseDeadline("2023-11-14T22:13:40Z", now: now)
    #expect(abs(parsed.timeIntervalSince1970 - 1_700_000_020) < 0.001)

    let fractional = FnContract.parseDeadline("2023-11-14T22:13:40.500Z", now: now)
    #expect(abs(fractional.timeIntervalSince1970 - 1_700_000_020.5) < 0.001)

    let defaulted = FnContract.parseDeadline(nil, now: now)
    #expect(abs(defaulted.timeIntervalSince(now) - 30) < 0.001)
  }

  @Test("decapsulateRequestHeaders strips Fn-Http-H-, keeps Content-Type, drops transport headers")
  func requestDecapsulation() {
    let incoming: [(name: String, value: String)] = [
      ("Fn-Http-H-Accept", "application/json"),
      ("Fn-Http-H-X-Custom", "abc"),
      ("Content-Type", "application/json"),
      ("Fn-Call-Id", "01AAA"),
      ("Fn-Http-Method", "POST"),
    ]
    let headers = FnContract.decapsulateRequestHeaders(incoming)
    #expect(headers["accept"] == "application/json")
    #expect(headers["X-Custom"] == "abc")
    #expect(headers["content-type"] == "application/json")
    #expect(headers["Fn-Call-Id"] == nil)
    #expect(headers["Fn-Http-Method"] == nil)
  }

  @Test("encapsulateResponseHeaders wraps HTTP-triggered responses with Fn-Http-Status + Fn-Http-H-*")
  func responseEncapsulationHTTP() {
    let response = FunctionResponse(
      status: 201,
      body: Data("ok".utf8),
      contentType: "text/plain",
      headers: ["X-Trace": "xyz"]
    )
    let out = FnContract.encapsulateResponseHeaders(response, isHTTPRequest: true)
    #expect(pair(out, "Fn-Http-Status") == "201")
    #expect(pair(out, "Fn-Http-H-X-Trace") == "xyz")
    #expect(pair(out, "Content-Type") == "text/plain")
    #expect(pair(out, "Fn-Fdk-Version") == FnFdk.version)
    #expect(pair(out, "Fn-Fdk-Runtime") == FnFdk.runtime)
    // The raw user header must not leak unprefixed.
    #expect(pair(out, "X-Trace") == nil)
  }

  @Test("encapsulateResponseHeaders leaves a plain invocation unwrapped (no Fn-Http-Status)")
  func responseEncapsulationPlain() {
    let response = FunctionResponse(status: 500, body: Data("raw".utf8), contentType: "application/octet-stream")
    let out = FnContract.encapsulateResponseHeaders(response, isHTTPRequest: false)
    #expect(pair(out, "Fn-Http-Status") == nil)
    #expect(pair(out, "Content-Type") == "application/octet-stream")
    #expect(pair(out, "Fn-Fdk-Version") == FnFdk.version)
  }

  @Test("HTTP-triggered Content-Type supplied via the headers dict is emitted unprefixed, not dropped")
  func responseContentTypeFromHeadersDict() {
    let response = FunctionResponse(
      status: 200,
      body: Data("x".utf8),
      contentType: nil,
      headers: ["Content-Type": "image/png"]
    )
    let out = FnContract.encapsulateResponseHeaders(response, isHTTPRequest: true)
    #expect(pair(out, "Content-Type") == "image/png")
    #expect(pair(out, "Fn-Http-H-Content-Type") == nil)  // never re-prefixed
  }

  @Test("plain invocation ignores handler headers and never forwards a framing Content-Length")
  func responsePlainDropsHandlerHeaders() {
    let response = FunctionResponse(
      status: 200,
      body: Data("raw".utf8),
      contentType: "text/plain",
      headers: ["Content-Length": "999", "X-Ignored": "yes"]
    )
    let out = FnContract.encapsulateResponseHeaders(response, isHTTPRequest: false)
    #expect(pair(out, "Content-Type") == "text/plain")
    #expect(pair(out, "Content-Length") == nil)  // the transport sets this, not the handler
    #expect(pair(out, "X-Ignored") == nil)
  }

  // MARK: - Helpers

  private func pair(_ list: [(name: String, value: String)], _ name: String) -> String? {
    list.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
  }
}
