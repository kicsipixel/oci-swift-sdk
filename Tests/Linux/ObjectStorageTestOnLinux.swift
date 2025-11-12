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

    @Test func putsObjectWithAPIKeySigner() async throws {
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

      // Correct Dropbox direct download URL
      guard let remoteURL = URL(string: "https://www.dropbox.com/scl/fi/eomsy2kohcjxqid7h1i7r/_.png?rlkey=z10i0f9jaum6cx5o2bpmjl5a2&dl=1") else {
        throw URLError(.badURL)
      }

      // Download to temporary location
      let (downloadedData, _) = try await URLSession.shared.data(from: remoteURL)
      let tempFileURL = FileManager.default.temporaryDirectory.appendingPathComponent("!@#$%^&*()_.png")
      try downloadedData.write(to: tempFileURL)

      do {
        try await sut.putObject(
          namespaceName: "frjfldcyl3la",
          bucketName: "test_bucket_by_sdk",
          objectName: "dropbox_image.png",
          putObjectBody: downloadedData
        )

        #expect(true, "The operation should succeed")
      } catch {
        Issue.record("putObject threw an error: \(error)")
      }
    }


  // MARK: - Lists objects with Observable
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
          print("ID: \(object.id ), Name: \(object.name), Size: \(size), Created: \(timeCreated)")
      }
    }
    #expect(!originalObjects.objects.isEmpty, "Expected non-empty object list after API execution")
  }
    
    // MARK: - Lists work requests
    @Test func listWorkRequestsWithAPIKeySigner() async throws {
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
        
        let listsWorkRequests = try? await sut.listWorkRequests(compartmentId: "ocid1.compartment.oc1..aaaaaaaatcmi2vv2tmuzgpajfncnqnvwvzkg2at7ez5lykdcarwtbeieyo2q")
        
        #expect(listsWorkRequests != nil, "The operation should succeed") 
    }
    
    // MARK: - Lists buckets
    /// Creates bucket must be proceed.
    @Test func listsBucketsWithAPIKeySignerReturnsMoreThanZero() async throws {
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

      let listOfBuckets = try await sut.listBuckets(
        namespaceName: "frjfldcyl3la",
        compartmentId: "ocid1.compartment.oc1..aaaaaaaatcmi2vv2tmuzgpajfncnqnvwvzkg2at7ez5lykdcarwtbeieyo2q"
      )

      // Lists all buckets in the compartment
      for bucket in listOfBuckets {
        print(bucket.name)
      }
      #expect(
        listOfBuckets.count > 0,
        "Number of buckets should be greater than zero"
      )
    }
    
    // MARK: -  Deletes object
    @Test func deletesObjectWithAPIKeySigner() async throws {
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

      let deleteObject: Void? = try? await sut.deleteObject(
        namespaceName: "frjfldcyl3la",
        bucketName: "test_bucket_by_sdk",
        objectName: "!@#$%^&*()_.png"
      )

      #expect(deleteObject != nil, "The operation should succeed")
    }
}
