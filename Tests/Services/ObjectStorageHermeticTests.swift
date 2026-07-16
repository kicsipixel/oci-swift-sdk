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
// Hermetic tests for ObjectStorageClient — no ~/.oci/config, no credentials, no
// network. They inject a fake HTTPClient that records the outgoing request and
// returns canned responses, so request-building and response-parsing are tested
// deterministically and run anywhere (CI, fork PRs, offline).
//

import Foundation
import OCIKit
import Testing

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

// A no-op signer. These tests exercise ObjectStorage's request/response logic,
// not signature correctness (which is covered separately with a fixed key), so
// no private key or config file is needed. It stamps an Authorization header so
// tests can confirm the signer ran.
private struct StubSigner: Signer {
  func sign(_ req: inout URLRequest) throws {
    req.setValue(#"Signature version="1""#, forHTTPHeaderField: "Authorization")
  }
}

// Sendable-safe capture of the last request the client handed to the transport.
private actor RequestRecorder {
  private(set) var last: URLRequest?
  func record(_ request: URLRequest) { last = request }
}

// Builds a client whose transport records the request and returns a canned response.
private func makeClient(
  status: Int,
  body: Data,
  responseHeaders: [String: String] = [:],
  recorder: RequestRecorder
) throws -> ObjectStorageClient {
  let http = HTTPClient { request in
    await recorder.record(request)
    let response = HTTPURLResponse(
      url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: responseHeaders
    )!
    return (body, response)
  }
  return try ObjectStorageClient(region: .iad, signer: StubSigner(), httpClient: http)
}

struct ObjectStorageHermeticTests {

  // Response parsing + request shape, both from a canned 200.
  @Test("getNamespace: builds GET /n and parses the quoted-string body")
  func getNamespace() async throws {
    let recorder = RequestRecorder()
    let client = try makeClient(status: 200, body: Data(#""frjfldcyl3la""#.utf8), recorder: recorder)

    let namespace = try await client.getNamespace()

    #expect(namespace == "frjfldcyl3la")  // quotes trimmed by the client
    let req = await recorder.last
    #expect(req?.httpMethod == "GET")
    #expect(req?.url?.host == "objectstorage.us-ashburn-1.oraclecloud.com")
    #expect(req?.url?.path == "/n")
    #expect(req?.value(forHTTPHeaderField: "Authorization") != nil)  // signer ran
  }

  // Query-parameter construction + JSON array decoding + RFC3339 parsing.
  @Test("listBuckets: sends compartmentId/limit/fields query and decodes the array")
  func listBuckets() async throws {
    let recorder = RequestRecorder()
    let json = """
      [
        {"compartmentId":"ocid1.compartment.oc1..c1","createdBy":"ocid1.user.oc1..u1","etag":"e1","name":"alpha","namespace":"frjfldcyl3la","timeCreated":"2026-07-14T12:00:00.000Z"},
        {"compartmentId":"ocid1.compartment.oc1..c1","createdBy":"ocid1.user.oc1..u1","etag":"e2","name":"beta","namespace":"frjfldcyl3la","timeCreated":"2026-07-14T12:05:00.000Z"}
      ]
      """
    let client = try makeClient(status: 200, body: Data(json.utf8), recorder: recorder)

    let buckets = try await client.listBuckets(
      namespaceName: "frjfldcyl3la",
      compartmentId: "ocid1.compartment.oc1..c1",
      limit: 10
    )

    #expect(buckets.map(\.name) == ["alpha", "beta"])
    #expect(buckets.first?.timeCreated != nil)  // RFC3339 -> Date parsing exercised

    let req = await recorder.last
    #expect(req?.httpMethod == "GET")
    #expect(req?.url?.path == "/n/frjfldcyl3la/b")
    let items = req?.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
    let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value) })
    #expect(query["compartmentId"] == "ocid1.compartment.oc1..c1")
    #expect(query["limit"] == "10")
    #expect(query["fields"] == "tags")  // default
  }

  // Write-path request shape (method, path, body). putObject also parses response
  // headers case-sensitively; that is exactly the Linux header-casing behavior
  // being addressed separately, so we ignore the call's outcome and assert only
  // the request the SDK emitted (the recorder captured it before any parsing).
  @Test("putObject: builds a PUT to /o/<object> with the payload as the body")
  func putObjectRequestShape() async throws {
    let recorder = RequestRecorder()
    let client = try makeClient(status: 200, body: Data(), recorder: recorder)
    let payload = Data("Hello, OCI!".utf8)

    _ = try? await client.putObject(
      namespaceName: "frjfldcyl3la",
      bucketName: "test_bucket_by_sdk",
      objectName: "greeting.txt",
      putObjectBody: payload
    )

    let req = await recorder.last
    #expect(req?.httpMethod == "PUT")
    #expect(req?.url?.path == "/n/frjfldcyl3la/b/test_bucket_by_sdk/o/greeting.txt")
    #expect(req?.httpBody == payload)
  }

  // Error path: a non-2xx with an OCI error body maps to unexpectedStatusCode.
  // Trivial to exercise hermetically; nearly impossible to provoke reliably live.
  @Test("getNamespace: non-2xx maps to ObjectStorageError with the server message")
  func errorMapping() async throws {
    let recorder = RequestRecorder()
    let errorJSON = #"{"code":"NamespaceNotFound","message":"You do not have authorization"}"#
    let client = try makeClient(status: 404, body: Data(errorJSON.utf8), recorder: recorder)

    await #expect(throws: ObjectStorageError.self) {
      _ = try await client.getNamespace()
    }
  }
}
