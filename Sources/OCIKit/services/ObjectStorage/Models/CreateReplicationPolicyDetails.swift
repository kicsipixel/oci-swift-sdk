//===----------------------------------------------------------------------=//
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

/// The details to create a replication policy.
public struct CreateReplicationPolicyDetails: Codable {
  /// The bucket to replicate to in the destination region. Replication policy creation does not automatically create a destination bucket. Create the destination bucket before creating the policy.
  public let destinationBucketName: String
  /// The destination region to replicate to, for example "us-ashburn-1".
  public let destinationRegionName: String
  /// The name of the policy. Avoid entering confidential information.
  public let name: String

  public init(destinationBucketName: String, destinationRegionName: String, name: String) {
    self.destinationBucketName = destinationBucketName
    self.destinationRegionName = destinationRegionName
    self.name = name
  }
}
