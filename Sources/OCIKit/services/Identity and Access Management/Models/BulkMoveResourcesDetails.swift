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

public struct BulkMoveResourcesDetails: Codable {
  /// The resources to be moved.
  public let resources: [BulkActionResource]

  /// The OCID of the destination compartment into which to move the resources.
  public let targetCompartmentId: String

  public init(resources: [BulkActionResource], targetCompartmentId: String) {
    self.resources = resources
    self.targetCompartmentId = targetCompartmentId
  }
}
