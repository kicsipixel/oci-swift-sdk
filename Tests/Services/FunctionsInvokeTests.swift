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
// Hermetic tests for FunctionsInvokeClient — no ~/.oci/config, no credentials, no
// network. They inject a fake HTTPClient that records the outgoing request and
// returns canned responses, so request-building and response-handling are tested
// deterministically and run anywhere (CI, fork PRs, offline).
//

import Foundation
import OCIKit
import Testing

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

// A no-op signer that stamps an Authorization header so tests can confirm it ran.
private struct StubSigner: Signer {
  func sign(_ req: inout URLRequest) throws {
    req.setValue(#"Signature version="1""#, forHTTPHeaderField: "Authorization")
  }
}

// Sendable-safe capture of the last request handed to the transport.
private actor RequestRecorder {
  private(set) var last: URLRequest?
  func record(_ request: URLRequest) { last = request }
}

private let invokeEndpoint = "https://aaaaaaaaexample.us-ashburn-1.functions.oci.oraclecloud.com"
private let functionOCID = "ocid1.fnfunc.oc1.iad.aaaaaaaaexamplefunctionocid"

private func makeClient(
  status: Int,
  body: Data,
  responseHeaders: [String: String] = [:],
  recorder: RequestRecorder
) throws -> FunctionsInvokeClient {
  let http = HTTPClient { request in
    await recorder.record(request)
    let response = HTTPURLResponse(
      url: request.url!,
      statusCode: status,
      httpVersion: "HTTP/1.1",
      headerFields: responseHeaders
    )!
    return (body, response)
  }
  return try FunctionsInvokeClient(invokeEndpoint: invokeEndpoint, signer: StubSigner(), httpClient: http)
}

@Suite("FunctionsInvokeClient")
struct FunctionsInvokeTests {

  @Test("invokeFunction POSTs to the per-function invoke path, sends the body, and returns raw bytes")
  func invokeShape() async throws {
    let recorder = RequestRecorder()
    let client = try makeClient(status: 200, body: Data("result-bytes".utf8), recorder: recorder)

    let output = try await client.invokeFunction(
      functionId: functionOCID,
      body: Data(#"{"name":"world"}"#.utf8),
      contentType: "application/json"
    )

    #expect(String(decoding: output, as: UTF8.self) == "result-bytes")
    let req = await recorder.last
    #expect(req?.httpMethod == "POST")
    #expect(req?.url?.host == "aaaaaaaaexample.us-ashburn-1.functions.oci.oraclecloud.com")
    #expect(req?.url?.path == "/20181201/functions/\(functionOCID)/actions/invoke")
    #expect(req?.value(forHTTPHeaderField: "accept") == "*/*")
    #expect(req?.value(forHTTPHeaderField: "Content-Type") == "application/json")
    #expect(req?.httpBody == Data(#"{"name":"world"}"#.utf8))
    #expect(req?.value(forHTTPHeaderField: "Authorization") != nil)  // signer ran
  }

  @Test("invokeFunction forwards fn-invoke-type, fn-intent, is-dry-run, and opc-request-id headers")
  func invokeHeaders() async throws {
    let recorder = RequestRecorder()
    let client = try makeClient(status: 200, body: Data(), recorder: recorder)

    _ = try await client.invokeFunction(
      functionId: functionOCID,
      invokeType: .detached,
      intent: .httprequest,
      isDryRun: true,
      opcRequestId: "req-123"
    )

    let req = await recorder.last
    #expect(req?.value(forHTTPHeaderField: "fn-invoke-type") == "detached")
    #expect(req?.value(forHTTPHeaderField: "fn-intent") == "httprequest")
    #expect(req?.value(forHTTPHeaderField: "is-dry-run") == "true")
    #expect(req?.value(forHTTPHeaderField: "opc-request-id") == "req-123")
  }

  @Test("invokeFunction defaults to application/octet-stream and omits optional headers")
  func invokeDefaults() async throws {
    let recorder = RequestRecorder()
    let client = try makeClient(status: 200, body: Data(), recorder: recorder)

    _ = try await client.invokeFunction(functionId: functionOCID)

    let req = await recorder.last
    #expect(req?.value(forHTTPHeaderField: "Content-Type") == "application/octet-stream")
    #expect(req?.value(forHTTPHeaderField: "fn-invoke-type") == nil)
    #expect(req?.value(forHTTPHeaderField: "fn-intent") == nil)
    #expect(req?.value(forHTTPHeaderField: "is-dry-run") == nil)
  }

  @Test("invokeFunction throws unexpectedStatusCode with the decoded error message on non-2xx")
  func invokeErrorStatus() async throws {
    let recorder = RequestRecorder()
    let errorBody = Data(#"{"code":"NotAuthorizedOrNotFound","message":"function not found"}"#.utf8)
    let client = try makeClient(status: 404, body: errorBody, recorder: recorder)

    await #expect(throws: FunctionsError.self) {
      _ = try await client.invokeFunction(functionId: functionOCID)
    }

    do {
      _ = try await client.invokeFunction(functionId: functionOCID)
      Issue.record("expected invokeFunction to throw")
    }
    catch let FunctionsError.unexpectedStatusCode(code, message) {
      #expect(code == 404)
      #expect(message == "function not found")
    }
  }

  @Test("invokeFunction rejects an empty functionId")
  func invokeEmptyId() async throws {
    let recorder = RequestRecorder()
    let client = try makeClient(status: 200, body: Data(), recorder: recorder)

    await #expect(throws: FunctionsError.self) {
      _ = try await client.invokeFunction(functionId: "   ")
    }
  }

  @Test("init rejects a malformed invoke endpoint")
  func invalidEndpoint() {
    #expect(throws: FunctionsError.self) {
      _ = try FunctionsInvokeClient(invokeEndpoint: "not a url", signer: StubSigner())
    }
  }

  @Test("a 202 detached response is treated as success")
  func detachedAccepted() async throws {
    let recorder = RequestRecorder()
    let client = try makeClient(status: 202, body: Data(), recorder: recorder)
    let output = try await client.invokeFunction(functionId: functionOCID, invokeType: .detached)
    #expect(output.isEmpty)
  }
}
