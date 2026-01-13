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

public struct CreateMultipartUploadDetails: Codable {
  /// The optional Cache-Control header that defines the caching behavior value to be returned in GetObject and HeadObject responses. Specifying values for this header has no effect on Object Storage behavior. Programs that read the object determine what to do based on the value provided. For example, you could use this header to identify objects that require caching restrictions.
  public let cacheControl: String?

  /// The optional Content-Disposition header that defines presentational information for the object to be returned in GetObject and HeadObject responses. Specifying values for this header has no effect on Object Storage behavior. Programs that read the object determine what to do based on the value provided. For example, you could use this header to let users download objects with custom filenames in a browser.
  public let contentDisposition: String?

  /// The optional Content-Encoding header that defines the content encodings that were applied to the object to upload. Specifying values for this header has no effect on Object Storage behavior. Programs that read the object determine what to do based on the value provided. For example, you could use this header to determine what decoding mechanisms need to be applied to obtain the media-type specified by the Content-Type header of the object.
  public let contentEncoding: String?

  /// The optional Content-Language header that defines the content language of the object to upload. Specifying values for this header has no effect on Object Storage behavior. Programs that read the object determine what to do based on the value provided. For example, you could use this header to identify and differentiate objects based on a particular language.
  public let contentLanguage: String?

  /// The optional Content-Type header that defines the standard MIME type format of the object to upload. Specifying values for this header has no effect on Object Storage behavior. Programs that read the object determine what to do based on the value provided. For example, you could use this header to identify and perform special operations on text only objects.
  public let contentType: String?

  /// Arbitrary string keys and values for the user-defined metadata for the object. Keys must be in "opc-meta-*" format. Avoid entering confidential information.
  public let metadata: [String: [String: String]]?

  /// The name of the object to which this multi-part upload is targeted. Avoid entering confidential information. Example: test/object1.log
  public let object: String?

  /// The storage tier that the object should be stored in. If not specified, the object will be stored in the same storage tier as the bucket.
  public let storageTier: StorageTier

  public init(
    cacheControl: String? = nil,
    contentDisposition: String? = nil,
    contentEncoding: String? = nil,
    contentLanguage: String? = nil,
    contentType: String? = nil,
    metadata: [String: [String: String]]? = nil,
    object: String? = nil,
    storageTier: StorageTier
  ) {
    self.cacheControl = cacheControl
    self.contentDisposition = contentDisposition
    self.contentEncoding = contentEncoding
    self.contentLanguage = contentLanguage
    self.contentType = contentType
    self.metadata = metadata
    self.object = object
    self.storageTier = storageTier
  }
}
