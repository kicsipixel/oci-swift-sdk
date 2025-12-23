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

/// The summary of a replication policy.
public struct ReplicationPolicySummary: Codable {
  /// The bucket to replicate to in the destination region. Replication policy creation does not automatically create a destination bucket. Create the destination bucket before creating the policy.
  public let destinationBucketName: String
  /// The destination region to replicate to, for example "us-ashburn-1".
  public let destinationRegionName: String
  /// The id of the replication policy.
  public let id: String
  /// The name of the policy.
  public let name: String
  /// The replication status of the policy. If the status is CLIENT_ERROR, once the user fixes the issue described in the status message, the status will become ACTIVE.
  public let status: ReplicationPolicyStatus
  /// A human-readable description of the status.
  public let statusMessage: String
  /// The date when the replication policy was created as per RFC 3339.
  public let timeCreated: String
  /// Changes made to the source bucket before this time has been replicated.
  /// Documentation issue. It can be `null` after creating it.
  public let timeLastSync: String?
}
