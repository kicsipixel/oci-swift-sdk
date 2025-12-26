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

public struct BulkActionResource: Codable {
  /// The resource-type. To get the list of supported resource-types use ListBulkActionResourceTypes API.
  public let entityType: String

  /// The resource OCID.
  public let identifier: String

  ///     Additional information that helps to identity the resource for bulk action.
  ///
  ///     The APIs to delete and move most resource types only require the resource identifier (ocid). But some resource-types require additional identifying information.
  ///
  ///     This information is provided in the resource's public API document. It is also available through the ListBulkActionResourceTypes API.
  ///
  ///     Example: The APIs to delete or move the buckets resource-type require namespaceName and bucketName to identify the resource, as shown in the APIs, DeleteBucket and UpdateBucket.
  ///
  ///     To add a bucket for bulk actions, specify namespaceName and bucketName in the metadata property as shown in this example
  ///```
  ///    {
  ///      "identifier": "<OCID_of_bucket>"
  ///      "entityType": "bucket",
  ///      "metadata":
  ///    {
  ///        "namespaceName": "sampleNamespace",
  ///        "bucketName": "sampleBucket"
  ///      }
  ///    }
  ///    ```
  public let metadata: [String: [String: String]]?

  public init(entityType: String, identifier: String, metadata: [String: [String: String]]? = nil) {
    self.entityType = entityType
    self.identifier = identifier
    self.metadata = metadata
  }
}
