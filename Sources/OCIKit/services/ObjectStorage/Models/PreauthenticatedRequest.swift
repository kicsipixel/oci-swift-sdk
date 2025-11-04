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

public struct PreauthenticatedRequest: Codable {
  /// The operation that can be performed on this resource.
  public let accessType: String
  /// The URI to embed in the URL when using the pre-authenticated request.
  public let accessUri: String
  /// Specifies whether a list operation is allowed on a PAR with accessType "AnyObjectRead" or "AnyObjectReadWrite". Deny: Prevents the user from performing a list operation. ListObjects: Authorizes the user to perform a list operation.
  public let bucketListingAction: String?
  /// The unique identifier to use when directly addressing the pre-authenticated request.
  public let id: String
  /// The user-provided name of the pre-authenticated request.
  public let name: String
  /// The name of the object that is being granted access to by the pre-authenticated request. Avoid entering confidential information. The object name can be null and if so, the pre-authenticated request grants access to the entire bucket. Example: test/object1.log
  public let objectName: String?
  /// The date when the pre-authenticated request was created as per specification RFC 3339.
  public let timeCreated: String
  /// The expiration date for the pre-authenticated request as per RFC 3339. After this date the pre-authenticated request will no longer be valid.
  public let timeExpires: String
  /// Undocument value for full path
  public let fullPath: String
}
