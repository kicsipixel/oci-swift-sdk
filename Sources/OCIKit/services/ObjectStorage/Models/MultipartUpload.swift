//===----------------------------------------------------------------------===//
//
// This source file is part of the oci-swift-sdk open source project
//
// Copyright (c) 2026 Szabolcs Tóth and the oci-swift-sdk project authors
// Licensed under MIT License
//
// See LICENSE for license information
// See CONTRIBUTORS.md for the list of oci-swift-sdk project authors
//
// SPDX-License-Identifier: MIT License
//
//===----------------------------------------------------------------------===//

import Foundation

public struct MultipartUpload: Codable {
  /// The bucket in which the in-progress multipart upload is stored.
  public let bucket: String

  /// The Object Storage namespace in which the in-progress multipart upload is stored.
  public let namespace: String

  /// The object name of the in-progress multipart upload.
  public let object: String

  /// The storage tier that the object is stored in.
  /// The date and time the upload was created, as described in RFC 2616.
  public let storageTier: StorageTier?

  /// The raw string value of the creation time from the server.
  public let timeCreatedRaw: String

  /// The unique identifier for the in-progress multipart upload.
  public let uploadId: String

  /// The date and time that the retention rule was created as a `Date`.
  public var timeCreated: Date? {
    Date.fromRFC3339(timeCreatedRaw)
  }

  // Custom CodingKeys to map raw string fields to their JSON keys
  private enum CodingKeys: String, CodingKey {
    case bucket
    case namespace
    case object
    case storageTier
    case timeCreatedRaw = "timeCreated"
    case uploadId
  }
}
