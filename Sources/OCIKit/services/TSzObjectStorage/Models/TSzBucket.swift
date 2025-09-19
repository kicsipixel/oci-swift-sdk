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

public enum AutoTiring: String {
    case disabled = "Disabled"
    case infrequentAccess = "InfrequentAccess"
}

public enum PublicAccessType: String {
    case noPublicAccess = "NoPublicAccess"
    case objectRead = "ObjectRead"
    case objectReadWithoutList = "ObjectReadWithoutList"
}

public enum StorageTier: String {
    case standard = "Standard"
    case archive = "Archive"
}

public enum Versoning: String {
    case enabled = "Enabled"
    case suspended = "Suspended"
    case disabled = "Disabled"
}

/// A bucket is a container for storing objects in a compartment within a namespace. A bucket is associated with a single compartment.
/// The compartment has policies that indicate what actions a user can perform on a bucket and all the objects in the bucket. For more information, see [Managing Buckets](Managing Buckets).
///
/// To use any of the API operations, you must be authorized in an IAM policy. If you are not authorized, talk to an administrator.
/// If you are an administrator who needs to write policies to give users access, see [Getting Started with Policies](Getting Started with Policies).
public struct Bucket {
    /// The approximate number of objects in the bucket. Count statistics are reported periodically. You will see a lag between what is displayed and the actual object count.
    public let approximateCount: Int?
    /// The approximate total size in bytes of all objects in the bucket. Size statistics are reported periodically. You will see a lag between what is displayed and the actual size of the bucket.
    public let approximateSize: Int?
    /// The auto tiering status on the bucket. A bucket is created with auto tiering Disabled by default.
    /// For auto tiering InfrequentAccess, objects are transitioned automatically between the 'Standard' and 'InfrequentAccess' tiers based on the access pattern of the objects.
    public let autoTiring: AutoTiring?
    /// The compartment ID in which the bucket is authorized.
    public let compartmentId: String
    /// The OCID of the user who created the bucket.
    public let createdBy: String
    /// Defined tags for this resource. Each key is predefined and scoped to a namespace.
    /// Example: {"Operations": {"CostCenter": "42"}}
    public let definedTags: [String: [String: String]]?
    /// The entity tag (ETag) for the bucket.
    public let etag: String
    /// Free-form tags for this resource. Each tag is a simple key-value pair with no predefined name, type, or namespace.
    /// Example: {"Department": "Finance"}
    public let freeformTags: [String: String]?
    /// The OCID of the bucket.
    public let id: String?
    /// Whether or not this bucket is read only. By default, isReadOnly is set to false. This will be set to 'true' when this bucket is configured as a destination in a replication policy.
    public let isReadOnly: Bool?
    /// The OCID of a master encryption key used to call the Key Management service to generate a data encryption key or to encrypt or decrypt a data encryption key.
    public let kmsKeyId: String?
    /// Arbitrary string keys and values for user-defined metadata.
    public let metadata: [String: String]?
    /// The name of the bucket. Avoid entering confidential information. Example: my-new-bucket1
    public let name: String
    /// The Object Storage namespace in which the bucket resides.
    let namespace: String
    /// Whether or not events are emitted for object state changes in this bucket.
    /// By default, objectEventsEnabled is set to false. Set objectEventsEnabled to true to emit events for object state changes.
    public let objectEventsEnabled: Bool?
    /// The entity tag (ETag) for the live object lifecycle policy on the bucket.
    public let objectLifecyclePolicyEtag: String?
    /// The type of public access enabled on this bucket. A bucket is set to NoPublicAccess by default, which only allows an authenticated caller to access the bucket and its contents.
    /// When ObjectRead is enabled on the bucket, public access is allowed for the GetObject, HeadObject, and ListObjects operations.
    /// When ObjectReadWithoutList is enabled on the bucket, public access is allowed for the GetObject and HeadObject operations.
    public let publicAccessType: PublicAccessType?
    /// Whether or not this bucket is a replication source. By default, replicationEnabled is set to false. This will be set to 'true' when you create a replication policy for the bucket.
    public let replicationEnabled: Bool?
    /// The storage tier type assigned to the bucket. A bucket is set to Standard tier by default, which means objects uploaded or copied to the bucket will be in the standard storage tier.
    /// When the Archive tier type is set explicitly for a bucket, objects uploaded or copied to the bucket will be stored in archive storage.
    /// The storageTier property is immutable after bucket is created.
    public let storageTier: StorageTier?
    /// The date and time the bucket was created, as described in RFC 2616.
    public let timeCreated: String
    /// The versioning status on the bucket. A bucket is created with versioning Disabled by default.
    /// For versioning Enabled, objects are protected from overwrites and deletes, by maintaining their version history.
    /// When versioning is Suspended, the previous versions will still remain but new versions will no longer be created when overwitten or deleted.
    public let versioning: Versoning?
}
