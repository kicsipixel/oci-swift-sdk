//===----------------------------------------------------------------------===//
//
// This source file is part of the oci-swift-sdk open source project
//
// Copyright (c) 2025 Ilia Sazonov and the oci-swift-sdk project authors
// Licensed under MIT License
//
// See LICENSE for license information
// See CONTRIBUTORS.md for the list of oci-swift-sdk project authors
//
// SPDX-License-Identifier: MIT License
//
//===----------------------------------------------------------------------===//

import Foundation

/// The contents of the secret, properties of the secret (and secret version),
/// and user-provided contextual metadata for the secret.
///
/// A secret bundle contains both the secret value and metadata about the secret version.
public struct SecretBundle: Codable, Sendable {
  /// The OCID of the secret.
  public let secretId: String

  /// The version number of the secret.
  public let versionNumber: Int

  /// The name of the secret version.
  ///
  /// Labels are unique across the different versions of a particular secret.
  public let versionName: String?

  /// The contents of the secret.
  ///
  /// This contains the actual secret value, typically Base64-encoded.
  public let secretBundleContent: SecretBundleContentDetails?

  /// A list of possible rotation states for the secret version.
  ///
  /// A secret version can be in multiple stages simultaneously
  /// (e.g., both CURRENT and LATEST).
  public let stages: [SecretStage]?

  /// Customer-provided contextual metadata for the secret.
  public let metadata: [String: String]?

  /// The time when the secret bundle was created, as a raw RFC3339 string.
  private let timeCreatedRaw: String?

  /// An optional property indicating when to delete the secret version,
  /// as a raw RFC3339 string.
  private let timeOfDeletionRaw: String?

  /// An optional property indicating when the secret version will expire,
  /// as a raw RFC3339 string.
  private let timeOfExpiryRaw: String?

  /// The time when the secret bundle was created.
  public var timeCreated: Date? {
    guard let raw = timeCreatedRaw else { return nil }
    return Date.fromRFC3339(raw)
  }

  /// The time when the secret version is scheduled for deletion.
  ///
  /// Example: `2019-04-03T21:10:29.600Z`
  public var timeOfDeletion: Date? {
    guard let raw = timeOfDeletionRaw else { return nil }
    return Date.fromRFC3339(raw)
  }

  /// The time when the secret version will expire.
  ///
  /// Example: `2019-04-03T21:10:29.600Z`
  public var timeOfExpiry: Date? {
    guard let raw = timeOfExpiryRaw else { return nil }
    return Date.fromRFC3339(raw)
  }

  enum CodingKeys: String, CodingKey {
    case secretId
    case versionNumber
    case versionName
    case secretBundleContent
    case stages
    case metadata
    case timeCreatedRaw = "timeCreated"
    case timeOfDeletionRaw = "timeOfDeletion"
    case timeOfExpiryRaw = "timeOfExpiry"
  }
}
