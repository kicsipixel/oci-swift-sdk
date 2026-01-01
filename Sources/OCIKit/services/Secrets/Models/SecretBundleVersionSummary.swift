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

/// The properties of the secret bundle.
///
/// Secret bundle version summary objects do not include the actual contents of the secret.
/// Use `getSecretBundle` to retrieve the full secret content.
public struct SecretBundleVersionSummary: Codable, Sendable {
  /// The OCID of the secret.
  public let secretId: String

  /// The version number of the secret.
  public let versionNumber: Int

  /// The version name of the secret bundle, as provided when the secret
  /// was created or last rotated.
  public let versionName: String?

  /// A list of possible rotation states for the secret bundle.
  ///
  /// A secret version can be in multiple stages simultaneously
  /// (e.g., both CURRENT and LATEST).
  public let stages: [SecretStage]?

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
    case stages
    case timeCreatedRaw = "timeCreated"
    case timeOfDeletionRaw = "timeOfDeletion"
    case timeOfExpiryRaw = "timeOfExpiry"
  }
}
