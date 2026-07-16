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
// Hermetic tests for SecretsClient — no ~/.oci/config, no credentials, no
// network. Two shapes are used:
//   • replay a committed fixture (captured once from real OCI by OCICaptureTests)
//     and assert on the decoded model — locks response parsing.
//   • inject a recording HTTPClient closure and assert on the request the client
//     built (method, path, query, headers) — locks request building.
// Both run anywhere (CI, fork PRs, offline).
//

import Foundation
import OCIKit
import Testing

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

// A no-op-ish signer. These tests exercise request building and response
// parsing, not signature correctness. It stamps an Authorization header so a
// request-shape test can confirm the signing path was reached.
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

struct SecretsHermeticTests {
  // Well-formed placeholder OCIDs matching the sanitized fixtures.
  private static let secretId = "ocid1.vaultsecret.oc1.phx.EXAMPLE"
  private static let vaultId = "ocid1.vault.oc1.phx.EXAMPLE"

  // Fixtures live next to this test file; resolve via #filePath so no SwiftPM
  // resource bundling is needed (the source tree is present at test time).
  private func fixtureURL(_ name: String) -> URL {
    URL(filePath: #filePath).deletingLastPathComponent().appending(path: "Fixtures/\(name)")
  }

  private func replayClient(_ fixture: String) throws -> SecretsClient {
    let http = try HTTPClient.replaying(fromFile: fixtureURL(fixture))
    return try SecretsClient(region: .phx, signer: StubSigner(), httpClient: http)
  }

  // Builds a client whose transport records the request and returns a canned response.
  private func recordingClient(
    status: Int = 200,
    body: Data,
    recorder: RequestRecorder
  ) throws -> SecretsClient {
    let http = HTTPClient { request in
      await recorder.record(request)
      let response = HTTPURLResponse(
        url: request.url!,
        statusCode: status,
        httpVersion: "HTTP/1.1",
        headerFields: [:]
      )!
      return (body, response)
    }
    return try SecretsClient(region: .phx, signer: StubSigner(), httpClient: http)
  }

  private func query(of req: URLRequest?) -> [String: String] {
    let items = req?.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
    return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
  }

  // MARK: - Response decoding (replay captured 200s)

  @Test("getSecretBundle decodes the bundle, stages, and Base64 content")
  func getSecretBundleDecodes() async throws {
    let client = try replayClient("getSecretBundle.json")

    let bundle = try await client.getSecretBundle(secretId: Self.secretId)

    #expect(bundle.secretId == Self.secretId)
    #expect(bundle.versionNumber == 2)
    #expect(bundle.versionName == nil)
    #expect(bundle.stages == [.current, .latest])
    #expect(bundle.metadata == nil)
    #expect(bundle.timeCreated != nil)  // RFC3339 -> Date parsing exercised
    // Polymorphic secret content decodes and Base64-unwraps.
    #expect(bundle.secretBundleContent?.contentType == .base64)
    #expect(bundle.secretBundleContent?.decodedString == "EXAMPLE-SECRET-VALUE")
  }

  @Test("listSecretBundleVersions decodes the array of version summaries")
  func listSecretBundleVersionsDecodes() async throws {
    let client = try replayClient("listSecretBundleVersions.json")

    let versions = try await client.listSecretBundleVersions(secretId: Self.secretId)

    #expect(versions.count == 2)
    #expect(versions.map(\.versionNumber) == [2, 1])
    #expect(versions.first?.stages == [.current, .latest])
    #expect(versions.last?.stages == [.previous])
    #expect(versions.first?.timeCreated != nil)  // RFC3339 -> Date parsing exercised
  }

  @Test("getSecretBundleByName decodes the same bundle shape as getSecretBundle")
  func getSecretBundleByNameDecodes() async throws {
    let client = try replayClient("getSecretBundleByName.json")

    let bundle = try await client.getSecretBundleByName(
      secretName: "EXAMPLE-secret",
      vaultId: Self.vaultId
    )

    #expect(bundle.secretId == Self.secretId)
    #expect(bundle.versionNumber == 2)
    #expect(bundle.secretBundleContent?.decodedString == "EXAMPLE-SECRET-VALUE")
  }

  // MARK: - Request shape (record the outgoing request)

  @Test("getSecretBundle: builds GET /secretbundles/<id> with versionNumber & stage query")
  func getSecretBundleRequestShape() async throws {
    let recorder = RequestRecorder()
    // Minimal valid SecretBundle so the call returns without throwing.
    let body = Data(#"{"secretId":"\#(Self.secretId)","versionNumber":3,"stages":["PENDING"]}"#.utf8)
    let client = try recordingClient(body: body, recorder: recorder)

    _ = try await client.getSecretBundle(
      secretId: Self.secretId,
      versionNumber: 3,
      stage: .current,
      opcRequestId: "req-abc"
    )

    let req = await recorder.last
    #expect(req?.httpMethod == "GET")
    #expect(req?.url?.host == "secrets.vaults.us-phoenix-1.oci.oraclecloud.com")
    #expect(req?.url?.path == "/20190301/secretbundles/\(Self.secretId)")
    let q = query(of: req)
    #expect(q["versionNumber"] == "3")
    #expect(q["stage"] == "CURRENT")
    #expect(req?.value(forHTTPHeaderField: "opc-request-id") == "req-abc")
    #expect(req?.value(forHTTPHeaderField: "Authorization") != nil)  // signer ran
  }

  @Test("getSecretBundleByName: uses POST to actions/getByName with secretName & vaultId query")
  func getSecretBundleByNameRequestShape() async throws {
    let recorder = RequestRecorder()
    let body = Data(#"{"secretId":"\#(Self.secretId)","versionNumber":2}"#.utf8)
    let client = try recordingClient(body: body, recorder: recorder)

    _ = try await client.getSecretBundleByName(
      secretName: "EXAMPLE-secret",
      vaultId: Self.vaultId,
      stage: .latest
    )

    let req = await recorder.last
    #expect(req?.httpMethod == "POST")  // read operation that uses POST
    #expect(req?.url?.path == "/20190301/secretbundles/actions/getByName")
    let q = query(of: req)
    #expect(q["secretName"] == "EXAMPLE-secret")
    #expect(q["vaultId"] == Self.vaultId)
    #expect(q["stage"] == "LATEST")
  }

  @Test("listSecretBundleVersions: builds GET /versions with limit/sortBy/sortOrder query")
  func listSecretBundleVersionsRequestShape() async throws {
    let recorder = RequestRecorder()
    let client = try recordingClient(body: Data("[]".utf8), recorder: recorder)

    _ = try await client.listSecretBundleVersions(
      secretId: Self.secretId,
      limit: 25,
      sortBy: .versionNumber,
      sortOrder: .desc
    )

    let req = await recorder.last
    #expect(req?.httpMethod == "GET")
    #expect(req?.url?.path == "/20190301/secretbundles/\(Self.secretId)/versions")
    let q = query(of: req)
    #expect(q["limit"] == "25")
    #expect(q["sortBy"] == "VERSION_NUMBER")
    #expect(q["sortOrder"] == "DESC")
  }

  // MARK: - Error mapping

  @Test("getSecretBundle: a captured 404 maps to SecretsError")
  func errorMapping() async throws {
    let client = try replayClient("getSecretBundle_404.json")

    await #expect(throws: SecretsError.self) {
      _ = try await client.getSecretBundle(secretId: Self.secretId)
    }
  }
}
