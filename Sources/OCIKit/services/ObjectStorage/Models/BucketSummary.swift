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

public struct BucketSummary: Decodable {
  /// The compartment ID in which the bucket is authorized.
  public let compartmentId: String

  /// The OCID of the user who created the bucket.
  public let createdBy: String

  /// Defined tags for this resource.
  /// Example: {"Operations": {"CostCenter": "42"}}
  public let definedTags: [String: [String: String]]?

  /// The entity tag (ETag) for the bucket.
  public let etag: String

  /// Free-form tags for this resource.
  /// Example: {"Department": "Finance"}
  public let freeformTags: [String: String]?

  /// The name of the bucket. Avoid entering confidential information.
  public let name: String

  /// The Object Storage namespace in which the bucket lives.
  public let namespace: String

  /// The raw string value of the creation time from the server.
  /// Format: RFC 3339 (e.g., "2025-11-09T20:26:04.123Z")
  private let timeCreatedRaw: String

  /// The date and time the bucket was created as a `Date`.
  public var timeCreated: Date? {
    Date.fromRFC3339(timeCreatedRaw)
  }

  // MARK: - CodingKeys
  private enum CodingKeys: String, CodingKey {
    case compartmentId
    case createdBy
    case definedTags
    case etag
    case freeformTags
    case name
    case namespace
    case timeCreatedRaw = "timeCreated"
  }

  /// Initializes a new `BucketSummary` instance.
  public init(
    compartmentId: String,
    createdBy: String,
    definedTags: [String: [String: String]]?,
    etag: String,
    freeformTags: [String: String]?,
    name: String,
    namespace: String,
    timeCreatedRaw: String
  ) {
    self.compartmentId = compartmentId
    self.createdBy = createdBy
    self.definedTags = definedTags
    self.etag = etag
    self.freeformTags = freeformTags
    self.name = name
    self.namespace = namespace
    self.timeCreatedRaw = timeCreatedRaw
  }
}