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
// Fixture REPLAY tests. The "hermetic" half: load a committed fixture (captured
// once by OCICaptureTests) and drive the client against it — no credentials, no
// network. Runs in CI and on fork PRs.
//

import Foundation
import OCIKit
import Testing

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

private struct ReplayStubSigner: Signer {
  func sign(_ req: inout URLRequest) throws {}
}

struct OCIFixtureReplayTests {
  // Fixtures live next to this test file; resolve via #filePath so no SwiftPM
  // resource bundling is needed (the source tree is present at test time).
  private func fixtureURL(_ name: String) -> URL {
    URL(filePath: #filePath).deletingLastPathComponent().appending(path: "Fixtures/\(name)")
  }

  @Test("getNamespace replays a captured OCI response with no network")
  func replayGetNamespace() async throws {
    let http = try HTTPClient.replaying(fromFile: fixtureURL("getNamespace.json"))
    let client = try ObjectStorageClient(region: .iad, signer: ReplayStubSigner(), httpClient: http)

    let namespace = try await client.getNamespace()

    #expect(namespace == "frjfldcyl3la")
  }

  @Test("the committed fixture round-trips through HTTPFixture")
  func fixtureDecodes() throws {
    let fixture = try HTTPFixture.load(fromFile: fixtureURL("getNamespace.json"))
    #expect(fixture.statusCode == 200)
    #expect(fixture.request.method == "GET")
    #expect(String(data: fixture.body, encoding: .utf8) == #""frjfldcyl3la""#)
    // The header the client reads for tracing was captured from the wire:
    #expect(fixture.headers.keys.contains { $0.lowercased() == "opc-request-id" })
  }
}
