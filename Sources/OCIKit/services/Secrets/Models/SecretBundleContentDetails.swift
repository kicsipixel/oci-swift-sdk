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

/// The contents of the secret.
///
/// This is a polymorphic type that uses `contentType` as the discriminator.
/// Currently, only Base64-encoded content is supported.
public enum SecretBundleContentDetails: Codable, Sendable {
  /// The secret content encoded as a Base64 string.
  case base64(content: String)

  private enum CodingKeys: String, CodingKey {
    case contentType
    case content
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let contentType = try container.decode(String.self, forKey: .contentType)

    switch contentType {
    case "BASE64":
      let content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
      self = .base64(content: content)
    default:
      // For forward compatibility, treat unknown types as base64 with empty content
      self = .base64(content: "")
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)

    switch self {
    case .base64(let content):
      try container.encode("BASE64", forKey: .contentType)
      try container.encode(content, forKey: .content)
    }
  }

  /// The content type of this secret bundle content.
  public var contentType: SecretContentType {
    switch self {
    case .base64:
      return .base64
    }
  }

  /// The raw content string.
  ///
  /// For Base64 content, this returns the Base64-encoded string.
  public var content: String {
    switch self {
    case .base64(let content):
      return content
    }
  }

  /// Decodes the Base64 content and returns it as `Data`.
  ///
  /// - Returns: The decoded data, or `nil` if the content is not valid Base64.
  public var decodedData: Data? {
    switch self {
    case .base64(let content):
      return Data(base64Encoded: content)
    }
  }

  /// Decodes the Base64 content and returns it as a UTF-8 string.
  ///
  /// - Returns: The decoded string, or `nil` if the content is not valid Base64
  ///   or cannot be decoded as UTF-8.
  public var decodedString: String? {
    guard let data = decodedData else { return nil }
    return String(data: data, encoding: .utf8)
  }
}
