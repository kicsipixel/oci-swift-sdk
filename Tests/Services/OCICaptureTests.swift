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
// Fixture CAPTURE tool. This is the "live" half: run it once, pointed at a real
// OCI endpoint, to record a response into a JSON fixture that hermetic tests then
// replay. It self-skips unless configured, so it never runs in normal CI.
//
// Capture against real OCI:
//   OCI_CAPTURE_BASE_URL=https://objectstorage.us-ashburn-1.oraclecloud.com \
//   OCI_CONFIG_FILE=$HOME/.oci/config OCI_PROFILE=DEFAULT \
//   OCI_FIXTURE_OUT=/tmp/fixtures \
//   swift test --filter OCICaptureTests
//
// (With a real config the request is signed by APIKeySigner so OCI accepts it;
// without one it falls back to a stub signer for hitting a local/mock endpoint.)
//

import Foundation
import OCIKit
import Testing

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

private struct CaptureStubSigner: Signer {
  func sign(_ req: inout URLRequest) throws {
    req.setValue(#"Signature version="1""#, forHTTPHeaderField: "Authorization")
  }
}

struct OCICaptureTests {
  @Test("captures getNamespace from a live endpoint into a replayable fixture")
  func captureGetNamespace() async throws {
    let env = ProcessInfo.processInfo.environment
    guard let base = env["OCI_CAPTURE_BASE_URL"], let out = env["OCI_FIXTURE_OUT"] else {
      print("OCICaptureTests skipped — set OCI_CAPTURE_BASE_URL and OCI_FIXTURE_OUT to record.")
      return
    }

    // Real OCI needs a real signature; a local mock endpoint does not.
    let signer: Signer
    if let configFile = env["OCI_CONFIG_FILE"] {
      signer = try APIKeySigner(configFilePath: configFile, configName: env["OCI_PROFILE"] ?? "DEFAULT")
    }
    else {
      signer = CaptureStubSigner()
    }

    let client = try ObjectStorageClient(
      endpoint: base,
      signer: signer,
      httpClient: .recording(into: URL(filePath: out))
    )

    let namespace = try await client.getNamespace()
    print("OCICaptureTests: captured getNamespace -> \"\(namespace)\"; fixture written under \(out)")
  }
}
