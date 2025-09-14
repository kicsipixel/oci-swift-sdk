//
//  ObjectStorageTest.swift
//  oci-swift-sdk
//
//  Created by Ilia Sazonov on 9/13/25.
//

import Foundation
import Testing
import OCIKit

struct ObjectStorageTest {
    let ociConfigFilePath: String
    let ociProfileName: String
    
    init() {
        let env = ProcessInfo.processInfo.environment
        ociConfigFilePath = env["OCI_CONFIG_FILE"] ?? "\(NSHomeDirectory())/.oci/config"
        ociProfileName = env["OCI_PROFILE"] ?? "DEFAULT"
        
        print("Using profile: \(ociProfileName)")
    }

    @Test func getNamespace_withAPIKeySigner() async throws {
        let regionId = try extractUserRegion(from: ociConfigFilePath, profile: ociProfileName)
        let region = Region.from(regionId: regionId ?? "") ?? .iad
        let signer = try APIKeySigner(configFilePath: ociConfigFilePath, configName: ociProfileName)
        let client = ObjectStorageClient(region: region, signer: signer)

        let namespace = try await client.getNamespace()
        print("Namespace: \(namespace)")
        #expect(!namespace.isEmpty)
    }

    @Test func getNamespace_withSecurityTokenSigner() async throws {
        let regionId = try extractUserRegion(from: ociConfigFilePath, profile: ociProfileName)
        let region = Region.from(regionId: regionId ?? "") ?? .iad
        let signer = try SecurityTokenSigner(configFilePath: ociConfigFilePath, configName: ociProfileName)
        let client = ObjectStorageClient(region: region, signer: signer)

        let namespace = try await client.getNamespace()
        print("Namespace: \(namespace)")
        #expect(!namespace.isEmpty)
    }
}
