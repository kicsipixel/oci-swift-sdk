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

/// The rotation state of the secret version.
///
/// Used to specify which version of a secret to retrieve based on its lifecycle stage.
public enum SecretStage: String, Codable, Sendable {
  /// The current active version of the secret.
  case current = "CURRENT"
  /// A version that is pending activation.
  case pending = "PENDING"
  /// The most recently created version.
  case latest = "LATEST"
  /// The previously active version.
  case previous = "PREVIOUS"
  /// A version that has been marked as deprecated.
  case deprecated = "DEPRECATED"
}

/// The field to sort by when listing secret bundle versions.
public enum SecretVersionSortBy: String, Codable, Sendable {
  /// Sort by version number (default order is descending).
  case versionNumber = "VERSION_NUMBER"
}

/// The formatting type of secret contents.
public enum SecretContentType: String, Codable, Sendable {
  /// The secret content is Base64-encoded.
  case base64 = "BASE64"
}
