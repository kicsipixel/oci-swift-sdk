//===----------------------------------------------------------------------===//
//
// This source file is part of the oci-swift-sdk open source project
//
// Copyright (c) 2025 Szabolcs Toth and the oci-swift-sdk project authors
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

struct ObjectStorageTest {
  let ociConfigFilePath: String
  let ociProfileName: String

  init() throws {
    let env = ProcessInfo.processInfo.environment
    ociConfigFilePath = env["OCI_CONFIG_FILE"] ?? "\(NSHomeDirectory())/.oci/config"
    ociProfileName = env["OCI_PROFILE"] ?? "DEFAULT"
  }

  // MARK: - Copies object
  /// This test fails with `400` for unknown reason.
  /// "code": "InsufficientServicePermissions",
  ///  "message": "Permissions granted to the object storage service principal \"objectstorage-eu-frankfurt-1\" to this bucket are insufficient."
  ///  "See [documentation](https://docs.oracle.com/iaas/Content/API/References/apierrors.htm) for more information about resolving this error. If you are unable to resolve this issue, run this CLI command with --debug option and contact Oracle support and provide them the full error message."
  @Test func copiesObjectWithinRegionWithAPIKeySigner() async throws {
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
    let object = CopyObjectDetails(
      destinationBucket: "Bucket_Parks_of_Prague",
      destinationNamespace: "frjfldcyl3la",
      destinationObjectName: "Frame.png",
      destinationRegion: "eu-frankfurt-1",
      sourceObjectName: "Frame.png"
    )

    let copyObject: Void? = try? await sut.copyObject(
      namespaceName: "frjfldcyl3la",
      bucketName: "test_bucket_by_sdk",
      copyObjectDetails: object
    )

    #expect(copyObject != nil, "The return value should not be nil")
  }

  // MARK: - Creates bucket
  @Test func createsBucketWithAPIKeySigner() async throws {
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
    let bucket = CreateBucketDetails(
      compartmentId: "ocid1.compartment.oc1..aaaaaaaatcmi2vv2tmuzgpajfncnqnvwvzkg2at7ez5lykdcarwtbeieyo2q",
      name: "test_bucket_by_sdk"
    )

    let createBucket = try await sut.createBucket(
      namespaceName: "frjfldcyl3la",
      createBucketDetails: bucket
    )

    // Prints the name of the new bucket
    if let createBucket {
      print(createBucket.name)
    }

    #expect(createBucket != nil, "The return value should not be nil")
  }

  @Test func createsArchiveBucketWithAPIKeySigner() async throws {
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
    let bucket = CreateBucketDetails(
      compartmentId: "ocid1.compartment.oc1..aaaaaaaatcmi2vv2tmuzgpajfncnqnvwvzkg2at7ez5lykdcarwtbeieyo2q",
      name: "archive_test_bucket_by_sdk",
      storageTier: StorageTier.archive
    )

    let createBucket = try await sut.createBucket(
      namespaceName: "frjfldcyl3la",
      createBucketDetails: bucket
    )

    // Prints the name of the new bucket
    if let createBucket {
      print(createBucket.name)
    }

    #expect(createBucket != nil, "The return value should not be nil")
  }

  // MARK: - Creates replication policy
  /// `Allow service objectstorage-eu-frankfurt-1 to manage object-family in compartment your_comparment_name`
  /// Always Free Tier allows only one policy
  @Test func createsReplicationPolicyWithAPIKeySigner() async throws {
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
    let replicationPolicy = CreateReplicationPolicyDetails(destinationBucketName: "test_bucket_by_sdk_replica", destinationRegionName: "eu-frankfurt-1", name: "Test_policy")

    let createReplicationPolicy = try await sut.createReplicationPolicy(namespaceName: "frjfldcyl3la", bucketName: "test_bucket_by_sdk", policyDetails: replicationPolicy)

    #expect(createReplicationPolicy != nil, "The operation should succeed")
  }

  // MARK: - Creates retention rule
  /// If the bucket versioning is enabled, you cannot add retention policy.
  /// `timeRuleLocked` must be atleast 14 days ahead of the current time.`
  @Test func createsRetentionRuleWithAPIKeySigner() async throws {
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
    let twoDaysFromNow = Calendar.current.date(byAdding: .day, value: 22, to: Date.now)
    let ruleDetails = CreateRetentionRuleDetails(displayName: "Test_retention", duration: Duration(timeAmount: 10, timeUnit: TimeUnit.days), timeRuleLocked: twoDaysFromNow?.toRFC3339())

    let createRetentionRule = try? await sut.createRetentionRule(namespaceName: "frjfldcyl3la", bucketName: "test_bucket_by_sdk", ruleDetails: ruleDetails)

    // Prints rule
    if let rule = createRetentionRule {
      print("You applied rule: \(rule.displayName).")
    }
    #expect(createRetentionRule != nil, "The operation should succeed")
  }

  // MARK: - Deletes bucket
  @Test func deletesBucketWithAPIKeySigner() async throws {
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

    let deleteBucket: Void? = try? await sut.deleteBucket(
      namespaceName: "frjfldcyl3la",
      bucketName: "test_bucket_by_sdk"
    )

    #expect(deleteBucket != nil, "The operation should succeed")
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
      objectName: "Frame.png"
    )

    #expect(deleteObject != nil, "The operation should succeed")
  }

  @Test func deletesObjectWithVersionIdWithAPIKeySigner() async throws {
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
      objectName: "bucket.svg",
      versionId: "e0de6bec-7543-411a-9ab8-3542669ea3b3"
    )

    #expect(deleteObject != nil, "The operation should succeed")
  }

  // MARK: - Deletes replication policy
  @Test func deletesReplicationPolicyWithAPIKeySigner() async throws {
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

    let deleteReplicationPolicy: Void? = try? await sut.deleteReplicationPolicy(
      namespaceName: "frjfldcyl3la",
      bucketName: "test_bucket_by_sdk",
      replicationId: "824de84a-295d-44ca-be44-23b2f627b1f1"
    )

    #expect(deleteReplicationPolicy != nil, "The operation should succeed")
  }

  // MARK: - Deletes retention rule
  @Test func deletesRetentionRuleWithAPIKeySigner() async throws {
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

    let deleteRetentionRule: Void? = try? await sut.deleteRetentionRule(
      namespaceName: "frjfldcyl3la",
      bucketName: "test_bucket_by_sdk",
      retentionRuleId: ""
    )

    #expect(deleteRetentionRule != nil, "The operation should succeed")
  }
  // MARK: - Gets bucket
  @Test func getsBucketWithAPIKeySigner() async throws {
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

    let createBucket = try await sut.getBucket(
      namespaceName: "frjfldcyl3la",
      bucketName: "test_bucket_by_sdk"
    )

    // Prints the name of the new bucket
    if let createBucket {
      print(
        "The bucket: \(createBucket.name) is in the compartment: \(createBucket.compartmentId), created by: \(createBucket.createdBy)"
      )
    }

    #expect(createBucket != nil, "The return value should not be nil")
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

  @Test func gestNamespaceWithAPIKeySignerAndCompartmentIdReturnsValidString() async throws {
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

    let namespace = try await sut.getNamespace(
      compartmentId: "ocid1.tenancy.oc1..aaaaaaaapt3esrvwldrfekea5ucasigr2nof7tjx6ysyb4oo3yiqgx2d72ha"
    )

    #expect(!namespace.isEmpty, "Namespace should not be empty")
  }

  // MARK: - Gets namespace metadata
  /// `{
  ///   "data": {
  ///       "default-s3-compartment-id": "ocid1.tenancy.oc1..aaaaaaaapt3esrvwldrfekea5ucasigr2nof7tjx6ysyb4oo3yiqgx2d72ha",
  ///       "default-swift-compartment-id": "ocid1.tenancy.oc1..aaaaaaaapt3esrvwldrfekea5ucasigr2nof7tjx6ysyb4oo3yiqgx2d72ha",
  ///       "namespace": "frjfldcyl3la"
  ///    }
  /// }`
  @Test func getsNamespaceMetadataWithAPIKeySigner() async throws {
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

    let getNamespaceMetadata = try? await sut.getNamespaceMetadata(
      namespaceName: "frjfldcyl3la"
    )

    // Prints metadata
    if let metadata = getNamespaceMetadata {
      print(
        "default-swift-compartment-id: \(metadata.defaultSwiftCompartmentId), \ndefault-s3-compartment-id: \(metadata.defaultS3CompartmentId), \nnamespace: \(metadata.namespace)"
      )
    }
    #expect(getNamespaceMetadata != nil, "The operation should succeed")
  }

  // MARK: - Gets object
  @Test func getsObjectWithAPIKeySigner() async throws {
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

    let getObject = try? await sut.getObject(namespaceName: "frjfldcyl3la", bucketName: "test_bucket_by_sdk", objectName: "bucket.svg")

    #expect(getObject != nil, "The operation should succeed")
  }

  // MARK: - Gets replication policy
  @Test func getsReplicationPolicyWithAPIKeySigner() async throws {
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

    let getReplicationPolicy: ReplicationPolicy? = try await sut.getReplicationPolicy(
      namespaceName: "frjfldcyl3la",
      bucketName: "test_bucket_by_sdk",
      replicationId: "824de84a-295d-44ca-be44-23b2f627b1f1"
    )

    // Print policy details
    if let policy = getReplicationPolicy {
      print("id: \(policy.id) - name: \(policy.name)")
    }
    #expect(getReplicationPolicy != nil, "The operation should succeed")
  }

    // MARK: - Gets retention rule
    @Test func getRetentionRuleWithAPIKeySigner() async throws {
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
        
        let getRetentionRule: RetentionRule? = try? await sut.getRetentionRule(
            namespaceName: "frjfldcyl3la",
            bucketName: "test_bucket_by_sdk",
            retentionRuleId: ""
        )
        
        // Prints retention rule
        if let rule = getRetentionRule {
            print("id: \(rule.id) - name: \(rule.displayName)")
        }
        #expect(getRetentionRule != nil, "The operation should succeed")
    }
    
  // MARK: - Heads bucket
  @Test func headsBucketWithAPIKeySigner() async throws {
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

    let headBucket: Void? = try? await sut.headBucket(
      namespaceName: "frjfldcyl3la",
      bucketName: "test_bucket_by_sdk"
    )

    #expect(headBucket != nil, "The operation should succeed")
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

  // MARK: - List replication policies
  @Test func listReplicationPoliciesWithAPIKeySigner() async throws {
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

    let listReplicationPolicies = try await sut.listReplicationPolicies(
      namespaceName: "frjfldcyl3la",
      bucketName: "test_bucket_by_sdk",
      limit: 10
    )

    // Print polices
    if let policies = listReplicationPolicies {
      for policy in policies {
        print("id: \(policy.id) - name: \(policy.name)")
      }
    }
    #expect(listReplicationPolicies != nil, "The operation should succeed")
  }

  // MARK: - List replication resources
  /// At least one replication policy is required on the queried bucket
  @Test func listReplicationResourcesWithAPIKeySigner() async throws {
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

    let listReplicationResources = try await sut.listReplicationPolicies(
      namespaceName: "frjfldcyl3la",
      bucketName: "test_bucket_by_sdk",
      limit: 10
    )

    // Print resources
    if let resources = listReplicationResources {
      for resource in resources {
        print("id: \(resource.id) - name: \(resource.name) - destination: \(resource.destinationBucketName)")
      }
    }
    #expect(listReplicationResources != nil, "The operation should succeed")
  }

  // MARK: - List objects
  @Test func listObjectsWithAPIKeySigner() async throws {
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

    // Allowed values are: name (default), size, etag, timeCreated, md5, timeModified, storageTier, archivalState
    let fields: [Field] = [.name, .size, .md5]
    let fieldsString = fields.map { $0.rawValue }.joined(separator: ",")
    let listOfObjects = try await sut.listObjects(
      namespaceName: "frjfldcyl3la",
      bucketName: "test_bucket_by_sdk",
      fields: fieldsString
    )

    if let name = listOfObjects?.objects.first?.name, let size = listOfObjects?.objects.first?.size, let md5 = listOfObjects?.objects.first?.md5 {
      print("The name of the file: \(name), size: \(size) and md5: \(md5)")
    }
    #expect(listOfObjects != nil, "The operation should succeed")
  }

  // MARK: - Lists object versions
  @Test func listObjectVersionsWithAPIKeySigner() async throws {
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

    // Allowed values are: name (default), size, etag, timeCreated, md5, timeModified, storageTier, archivalState
    let fields: [Field] = [.name, .size, .md5]
    let fieldsString = fields.map { $0.rawValue }.joined(separator: ",")
    let listOfObjectVersions = try? await sut.listObjectVersions(
      namespaceName: "frjfldcyl3la",
      bucketName: "test_bucket_by_sdk",
      fields: fieldsString
    )

    // Prints versions
    if let versions = listOfObjectVersions?.items {
      for version in versions {
        print("File: \(version.name), size: \(version.size ?? 0), md5: \(version.md5 ?? "") and version: \(version.versionId)")
      }
    }
    #expect(listOfObjectVersions != nil, "The operation should succeed")
  }

  // MARK: - Makes bucket writable
  @Test func makeBucketWritableWithAPIKeySigner() async throws {
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

    let makeBucketWritable: ()? = try? await sut.makeBucketWritable(namespaceName: "frjfldcyl3la", bucketName: "test_bucket_by_sdk_replica")

    #expect(makeBucketWritable != nil, "The operation should succeed")
  }

  // MARK: - Puts object
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
    let fileToUploadPath = NSHomeDirectory() + "/Desktop/Frame.png"
    let fileToUploadURL = URL(fileURLWithPath: fileToUploadPath)
    let data: Data = try Data(contentsOf: fileToUploadURL)

    let putObject: Void? = try? await sut.putObject(
      namespaceName: "frjfldcyl3la",
      bucketName: "test_bucket_by_sdk",
      objectName: "\(fileToUploadURL.lastPathComponent)",
      putObjectBody: data
    )

    #expect(putObject != nil, "The operation should succeed")
  }

  // MARK: - Reencrypts bucket
  ///  If you call this API and there is no kmsKeyId associated with the bucket, the call will fail.
  @Test func reencryptsBucketWithAPIKeySigner() async throws {
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

    let reencryptBucket: Void? = try? await sut.reencryptBucket(
      namespaceName: "frjfldcyl3la",
      bucketName: "test_bucket_by_sdk"
    )

    #expect(reencryptBucket != nil, "The operation should succeed")
  }

  // MARK: - Reencrypts object
  @Test func reencryptsObjectWithAPIKeySigner() async throws {
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
    // If the request payload is empty, the object is encrypted using the encryption key assigned to the bucket.
    let reecryptObjectDetails = ReencryptObjectDetails()

    let reencryptObject: Void? = try? await sut.reencryptObject(
      namespaceName: "frjfldcyl3la",
      bucketName: "test_bucket_by_sdk",
      objectName: "Frame.png",
      reencryptObjectDetails: reecryptObjectDetails
    )

    #expect(reencryptObject != nil, "The operation should succeed")
  }

  // MARK: - Renames object
  @Test func renamesObjectWithAPIKeySigner() async throws {
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
    let renameObjectDetails = RenameObjectDetails(newName: "New Frame.png", sourceName: "Frame.png")

    let renameObject: Void? = try? await sut.renameObject(
      namespaceName: "frjfldcyl3la",
      bucketName: "test_bucket_by_sdk",
      renameObjectDetails: renameObjectDetails
    )

    #expect(renameObject != nil, "The operation should succeed")
  }

  // MARK: - Restore object
  @Test func restoreObjectWithAPIKeySigner() async throws {
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
    let restoreObjectDetails = RestoreObjectsDetails(objectName: "Frame.png")

    let restoreObject: Void? = try? await sut.restoreObject(
      namespaceName: "frjfldcyl3la",
      bucketName: "test_bucket_by_sdk",
      restoreObjectsDetails: restoreObjectDetails
    )

    #expect(restoreObject != nil, "The operation should succeed")
  }

  // MARK: - Updates bucket
  @Test func updatesBucketWithMovingToCompartmentWithAPIKeySigner() async throws {
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
    let bucket = UpdateBucketDetails(
      compartmentId: "ocid1.compartment.oc1..aaaaaaaatcmi2vv2tmuzgpajfncnqnvwvzkg2at7ez5lykdcarwtbeieyo2q"
    )

    let updateBucket: Bucket? = try? await sut.updateBucket(
      namespaceName: "frjfldcyl3la",
      bucketName: "test_bucket_by_sdk",
      updateBucketDetails: bucket
    )

    if let updateBucket {
      print(updateBucket.name)
    }

    // Prints the new name of the updated bucket
    if let updateBucket {
      print(updateBucket.name)
    }
    #expect(updateBucket != nil, "The return value should not be nil")
  }

  // Once a bucket versioning was "Enabled" you can "Suspend" it only.
  @Test func updatesBucketWithVersioningWithAPIKeySigner() async throws {
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
    let bucket = UpdateBucketDetails(versioning: Versoning.suspended)

    let updateBucket: Bucket? = try? await sut.updateBucket(
      namespaceName: "frjfldcyl3la",
      bucketName: "test_bucket_by_sdk",
      updateBucketDetails: bucket
    )

    if let updateBucket {
      print(updateBucket.name)
    }

    // Prints the new name of the updated bucket
    if let updateBucket {
      print(updateBucket.name)
    }
    #expect(updateBucket != nil, "The return value should not be nil")
  }

  // MARK: - Updates namespace meatadata
  @Test func updatesNamespaceMetadataWithAPIKeySigner() async throws {
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
    let metadata = UpdateNamespaceMetadataDetails(
      defaultS3CompartmentId: "ocid1.compartment.oc1..aaaaaaaar3gnsxd7vomtvklspmmmjl5i43vd6umbuqa3f6vtgsfmmk4oeuwa",
      defaultSwiftCompartmentId: "ocid1.compartment.oc1..aaaaaaaar3gnsxd7vomtvklspmmmjl5i43vd6umbuqa3f6vtgsfmmk4oeuwa"
    )

    let updateNamespaceMetadata = try? await sut.updateNamespaceMetadata(
      namespaceName: "frjfldcyl3la",
      metadata: metadata
    )

    // Prints metadata
    if let updateNamespaceMetadata {
      print(
        "default-swift-compartment-id: \(updateNamespaceMetadata.defaultSwiftCompartmentId), \ndefault-s3-compartment-id: \(updateNamespaceMetadata.defaultS3CompartmentId), \nnamespace: \(updateNamespaceMetadata.namespace)"
      )
    }
    #expect(updateNamespaceMetadata != nil, "The operation should succeed")
  }

  // MARK: - Updates object storage tier
  @Test func updatesObjectStorageTierWithAPIKeySigner() async throws {
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
    let updateObjectStorageTierDetails = UpdateObjectStorageTierDetails(
      objectName: "Frame.png",
      storageTier: StorageTier.infrequentAccess
    )

    let updateObjectStorageTier: Void? = try? await sut.updateObjectStorageTier(
      namespaceName: "frjfldcyl3la",
      bucketName: "test_bucket_by_sdk",
      updateObjectStorageTierDetails: updateObjectStorageTierDetails
    )

    #expect(updateObjectStorageTier != nil, "The operation should succeed")
  }
}
