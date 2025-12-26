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

public struct UpdateCompartmentDetails: Codable {
  /// Defined tags for this resource. Each key is predefined and scoped to a namespace. For more information, see Resource Tags. Example: {"Operations": {"CostCenter": "42"}}
  public let definedTags: [String: [String: String]]?

  /// The description you assign to the compartment. Does not have to be unique, and it's changeable.
  public let description: String?

  ///  Free-form tags for this resource. Each tag is a simple key-value pair with no predefined name, type, or namespace. For more information, see Resource Tags. Example: {"Department": "Finance"}
  public let freeformTags: [String: String]?

  /// The name you assign to the compartment during creation. The name must be unique across all compartments in the parent. Avoid entering confidential information.
  public let name: String?

  public init(defineTags: [String: [String: String]]? = nil, description: String? = nil, freeformTags: [String: String]? = nil, name: String? = nil) {
    self.definedTags = defineTags
    self.description = description
    self.freeformTags = freeformTags
    self.name = name
  }
}
