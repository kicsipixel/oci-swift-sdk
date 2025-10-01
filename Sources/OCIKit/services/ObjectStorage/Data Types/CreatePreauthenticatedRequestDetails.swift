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

public struct CreatePreauthenticatedRequestDetails: Codable {
  /// The operation that can be performed on this resource.
  public let accessType: AccessType
  /// Specifies whether a list operation is allowed on a PAR with accessType "AnyObjectRead" or "AnyObjectReadWrite". Deny: Prevents the user from performing a list operation. ListObjects: Authorizes the user to perform a list operation.
  public let bucketListingAction: BucketListingAction?
  /// A user-specified name for the pre-authenticated request. Names can be helpful in managing pre-authenticated requests. Avoid entering confidential information.
  public let name: String
  ///The name of the object that is being granted access to by the pre-authenticated request. Avoid entering confidential information. The object name can be null and if so, the pre-authenticated request grants access to the entire bucket if the access type allows that. The object name can be a prefix as well, in that case pre-authenticated request grants access to all the objects within the bucket starting with that prefix provided that we have the correct access type.
  ///  Default: object name is required for "ObjectRead", "ObjectWrite" or "ObjectReadWrite" accessType. It is optional and can be passed as a prefix for all other accessTypes, by default "null" will be assigned
  let objectName: String?
  /// The expiration date for the pre-authenticated request as per RFC 3339. After this date the pre-authenticated request will no longer be valid.
  public let timeExpires: String?

  public init(accessType: AccessType, bucketListingAction: BucketListingAction? = nil, name: String, objectName: String? = nil, timeExpires: String? = nil) {
    self.accessType = accessType
    self.bucketListingAction = bucketListingAction
    self.name = name
    self.objectName = objectName
    self.timeExpires = timeExpires
  }
}

public enum AccessType: String, Codable {
  case objectRead = "ObjectRead"
  case objectWrite = "ObjectWrite"
  case objectReadWrite = "ObjectReadWrite"
  case anyObjectWrite = "AnyObjectWrite"
  case anyObjectRead = "AnyObjectRead"
  case anyObjectReadWrite = "AnyObjectReadWrite"
}

public enum BucketListingAction: String, Codable {
  case deny = "Deny"
  case listObjects = "ListObjects"
}
