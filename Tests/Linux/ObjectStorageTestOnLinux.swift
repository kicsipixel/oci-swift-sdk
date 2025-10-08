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

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

struct ObjectStorageTestOnLinux {
  let ociConfigFilePath: String
  let ociProfileName: String

  init() throws {
    let env = ProcessInfo.processInfo.environment
    ociConfigFilePath = env["OCI_CONFIG_FILE"] ?? "\(NSHomeDirectory())/.oci/config"
    ociProfileName = env["OCI_PROFILE"] ?? "DEFAULT"
  }

  // MARK: - Gets namespace
  // Returns with a string. e.g.:"frjfldcyl3la"
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

  // MARK: - List objects with Observable
  // Returning with `name`, `size`, `timeCreated` and `timeModified`
  @Test func listObjectsObservableWithAPIKeySigner() async throws {
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
    let originalObjects = ListObjects(nextStartWith: nil, objects: [], prefixes: nil)

    let receivedObjects = try await sut.listObjects(
      namespaceName: "frjfldcyl3la",
      bucketName: "test_bucket_by_sdk"
    )

    // Update the `originalObjects` after API execution
    originalObjects.objects = receivedObjects.objects

    // Print objects
    for object in originalObjects.objects {
      if let timeCreated = object.timeCreated, let size = object.size {
        print("The name of the file: \(object.name), size: \(size) on \(timeCreated)")
      }
    }
    #expect(!originalObjects.objects.isEmpty, "Expected non-empty object list after API execution")
  }
}
