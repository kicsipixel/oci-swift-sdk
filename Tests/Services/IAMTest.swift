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

struct IAMTest {
  let ociConfigFilePath: String
  let ociProfileName: String

  init() throws {
    let env = ProcessInfo.processInfo.environment
    ociConfigFilePath = env["OCI_CONFIG_FILE"] ?? "\(NSHomeDirectory())/.oci/config"
    ociProfileName = env["OCI_PROFILE"] ?? "DEFAULT"
  }

  // MARK: - Creates a compartment
  @Test("Creates a compartment into the specified tenancy/comaprtment")
  func createCompartmentWithAPIKeySigner() async throws {
    let regionId = try extractUserRegion(
      from: ociConfigFilePath,
      profile: ociProfileName
    )
    let region = Region.from(regionId: regionId ?? "") ?? .iad
    let signer = try APIKeySigner(
      configFilePath: ociConfigFilePath,
      configName: ociProfileName
    )
    let sut = try IAMClient(region: region, signer: signer)

    let newCompartment = CreateCompartmentDetails(
      compartmentId: "ocid1.tenancy.oc1..aaaaaaaapt3esrvwldrfekea5ucasigr2nof7tjx6ysyb4oo3yiqgx2d72ha",
      description: "Compartment created by oci-swift-sdk.",
      name: "NewCompartment"
    )

    let createdCompartment = try? await sut.createCompartment(compartmentDetails: newCompartment)

    // Print created compartment
    if let compartment = createdCompartment {
      print("Compartment created: \(compartment.name)")
    }
    #expect(createdCompartment != nil, "createdCompartment should not be nil")
  }

  // MARK: - Deletes compartment
  @Test("Deletes the specified compartment")
  func deleteCompartmentWithAPIKeySigner() async throws {
    let regionId = try extractUserRegion(
      from: ociConfigFilePath,
      profile: ociProfileName
    )
    let region = Region.from(regionId: regionId ?? "") ?? .iad
    let signer = try APIKeySigner(
      configFilePath: ociConfigFilePath,
      configName: ociProfileName
    )
    let sut = try IAMClient(region: region, signer: signer)

    let deleteCompartment: ()? = try? await sut.deleteCompartment(compartmentId: "ocid1.compartment.oc1..aaaaaaaaun4hukknl7pzxq3nttbidqqoufrpfksxp7rqpkzc5ub36v4hu7rq")

    #expect(deleteCompartment != nil, "deleteCompartment should not be nil")
  }
  // MARK: - Lists compartments
  @Test("Returns with list of compartments in the same tenancy/compartment")
  func listCompartmentsWithAPIKeySigner() async throws {
    let regionId = try extractUserRegion(
      from: ociConfigFilePath,
      profile: ociProfileName
    )
    let region = Region.from(regionId: regionId ?? "") ?? .iad
    let signer = try APIKeySigner(
      configFilePath: ociConfigFilePath,
      configName: ociProfileName
    )
    let sut = try IAMClient(region: region, signer: signer)

    let listOfCompartments = try? await sut.listCompartments(compartmentId: "ocid1.tenancy.oc1..aaaaaaaapt3esrvwldrfekea5ucasigr2nof7tjx6ysyb4oo3yiqgx2d72ha")

    // Listing compartments
    if let compartments = listOfCompartments {
      for compartment in compartments {
        print("Compartment: \(compartment.name)")
      }
    }
    #expect(listOfCompartments != nil, "Expected a non-nil list of compartments")
  }
}
