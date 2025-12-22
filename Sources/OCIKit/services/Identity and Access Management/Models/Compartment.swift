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

public enum AccessLevel: String, Codable {
  case any = "ANY"
  case accessible = "ACCESSIBLE"
}

public enum SortBy: String, Codable {
  case timeCreated = "TIMECREATED"
  case name = "NAME"
}

public enum SortOrder: String, Codable {
  case asc = "ASC"
  case desc = "DESC"
}

public enum LifecycleState: String, Codable {
  case creating = "CREATING"
  case active = "ACTIVE"
  case inactive = "INACTIVE"
  case deleting = "DELETING"
  case deleted = "DELETED"
}

/// A collection of related resources. Compartments are a fundamental component of Oracle Cloud Infrastructure for organizing and isolating your cloud resources
public struct Compartment: Codable {
  /// The OCID of the parent compartment containing the compartment.
  public let compartmentId: String
  /// Defined tags for this resource. Each key is predefined and scoped to a namespace. For more information, see Resource Tags. Example: {"Operations": {"CostCenter": "42"}}
  public let definedTags: [String: [String: String]]?
  /// The description you assign to the compartment. Does not have to be unique, and it's changeable.
  public let description: String
  ///  Free-form tags for this resource. Each tag is a simple key-value pair with no predefined name, type, or namespace. For more information, see Resource Tags. Example: {"Department": "Finance"}
  public let freeformTags: [String: String]?
  /// The OCID of the compartment.
  public let id: String
  /// The detailed status of INACTIVE lifecycleState.
  public let inactiveStatus: Int?
  /// Indicates whether or not the compartment is accessible for the user making the request. Returns true when the user has INSPECT permissions directly on a resource in the compartment or indirectly (permissions can be on a resource in a subcompartment).
  public let isAccessible: Bool?
  /// The compartment's current state. After creating a compartment, make sure its lifecycleState changes from CREATING to ACTIVE before using it.
  public let lifecycleState: LifecycleState
  /// The name you assign to the compartment during creation. The name must be unique across all compartments in the parent. Avoid entering confidential information.
  public let name: String
  /// Date and time the compartment was created, in the format defined by RFC3339.
  private let timeCreatedRaw: String

  /// The date and time that the retention rule was created as a `Date`.
  public var timeCreated: Date? {
    Date.fromRFC3339(timeCreatedRaw)
  }

  // Custom CodingKeys to map raw string fields to their JSON keys
  enum CodingKeys: String, CodingKey {
    case compartmentId
    case definedTags
    case description
    case freeformTags
    case id
    case inactiveStatus
    case isAccessible
    case lifecycleState
    case name
    case timeCreatedRaw = "timeCreated"
  }
}
