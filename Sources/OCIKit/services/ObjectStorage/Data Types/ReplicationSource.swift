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

/// The details of a replication source bucket that replicates to a target destination bucket.
public struct ReplicationSource: Codable {
  /// The name of the policy.
  public let policyName: String
  /// The source bucket replicating data from.
  public let sourceBucketName: String
  /// The source region replicating data from, for example "us-ashburn-1".
  public let sourceRegionName: String
}
