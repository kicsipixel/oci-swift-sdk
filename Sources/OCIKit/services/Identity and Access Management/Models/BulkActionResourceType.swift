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

public struct BulkActionResourceType: Codable {

  /// List of metadata keys required to identify a specific resource. Some resource-types require information besides an OCID to identify a specific resource. For example, the resource-type buckets requires metadataKeys ["namespaceName", "bucketName"] to identify a specific bucket. The required information to identify a resource is in the API documentation for the resource-type. For example, the required information for buckets is found in the DeleteBucket API.
  public let metadataKeys: [String]?

  /// The unique name of the resource-type.
  public let name: String
}
