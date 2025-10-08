//===----------------------------------------------------------------------===//
//
// This source file is part of the oci-swift-sdk open source project
//
// Copyright (c) 2025 Szabolcs Tóth and the oci-swift-sdk project authors
// Licensed under MIT License
//
// See LICENSE for license information
// See CONTRIBUTORS.md for the list of oci-swift-sdk project authors
//
// SPDX-License-Identifier: MIT License
//
//===----------------------------------------------------------------------===//

import Foundation
import OCIKit
import Testing

struct ObjectStorageTestOnLinux {
    let ociConfigFilePath: String
    let ociProfileName: String
    
    init() throws {
        let env = ProcessInfo.processInfo.environment
        ociConfigFilePath = env["OCI_CONFIG_FILE"] ?? "\(NSHomeDirectory())/.oci/config"
        ociProfileName = env["OCI_PROFILE"] ?? "DEFAULT"
    }
    
    // MARK: - Gets namespace
    @Test func getsNamespaceWithAPIKeySignerReturnsValidString() async throws {
      let regionId = try extractUserRegion(
        from: ociConfigFilePath,
        profile: ociProfileName
      )
      let region = Region.from(regionId: regionId ?? "") ?? .iad
      let signer = try APIKeySigner(
        configFilePath: ociConfigFilePath,
        configName: ociProfileName
      )
      let sut = try ObjectStorageClient(region: region, signer: signer)

      let namespace = try await sut.getNamespace()

      // Prints the namespace
      print("The current namespace is: \(namespace)")
      #expect(!namespace.isEmpty, "Namespace should not be empty")
    }
}
