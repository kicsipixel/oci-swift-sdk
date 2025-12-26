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

public struct MoveCompartmentDetails: Codable {

  /// The OCID of the destination compartment into which to move the compartment.
  public let targetCompartmentId: String

  public init(targetCompartmentId: String) {
    self.targetCompartmentId = targetCompartmentId
  }
}
