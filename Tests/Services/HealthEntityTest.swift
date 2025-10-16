//
//  HealthEntityTest.swift
//  oci-swift-sdk
//
//  Created by Ilia Sazonov on 10/12/25.
//

import Foundation
import Testing
import OCIKit

struct HealthEntityTest {
  let ociConfigFilePath: String
  let ociProfileName: String
  
  init() throws {
    let env = ProcessInfo.processInfo.environment
    ociConfigFilePath = env["OCI_CONFIG_FILE"] ?? "\(NSHomeDirectory())/.oci/config"
    ociProfileName = env["OCI_PROFILE"] ?? "DEFAULT"
  }
  
  @Test func testHealthNER() async throws {
    guard let endpoint = ProcessInfo.processInfo.environment["HEALTH_NER_ENDPOINT"], !endpoint.isEmpty else {
      print("testHealthNER not configured")
      return
    }
    print("ociProfileName: \(ociProfileName)")
    let signer = try APIKeySigner(configFilePath: ociConfigFilePath, configName: ociProfileName)
    let healthNER = BatchDetectHealthEntity(region: .iad, signer: signer)
    let req = BatchDetectHealthEntity.BatchDetectHealthEntityDetails(
      documents: [TextDocument(key: UUID().uuidString, languageCode: "en", text: "lung cancer")],
      endpointId: endpoint,
      isDetectAssertions: true,
      isDetectRelationships: true
    )
    let response = try await healthNER.getHealthEntities(req)
    print("reponse: \(response)")
  }
}
