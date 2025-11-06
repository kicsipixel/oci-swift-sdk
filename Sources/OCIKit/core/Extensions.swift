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

import Crypto
import Foundation

extension Date {
  /// Creates a `Date` instance from a string in RFC3339 / ISO8601 format.
  ///
  /// This is useful when working with APIs that return timestamps in
  /// standard RFC3339 format, e.g. `"2025-10-01T19:23:45.123Z"`.
  ///
  /// - Parameter string: The RFC3339 formatted date string.
  /// - Returns: A `Date` if the string could be parsed, otherwise `nil`.
  ///
  /// ### Example
  /// ```swift
  /// let dateString = "2025-10-01T19:23:45.123Z"
  /// if let date = Date.fromRFC3339(dateString) {
  ///     print("Parsed date:", date)
  /// }
  /// ```
  public static func fromRFC3339(_ string: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: string)
  }

  /// Converts a `Date` instance into an RFC3339 / ISO8601 formatted string.
  ///
  /// Useful for sending dates to APIs that expect timestamps in RFC3339 format.
  ///
  /// - Returns: A `String` in RFC3339 format, e.g. `"2025-10-01T19:23:45.123Z"`.
  ///
  /// ### Example
  /// ```swift
  /// let now = Date()
  /// let rfc3339String = now.toRFC3339()
  /// print(rfc3339String) // e.g. "2025-10-01T19:23:45.123Z"
  /// ```
  public func toRFC3339() -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: self)
  }
}

extension Data {
  /// Computes the MD5 hash of the data and returns it as a lowercase hexadecimal string.
  ///
  /// This is useful for verifying data integrity or generating consistent identifiers.
  ///
  /// Example:
  /// ```swift
  /// let data = "hello".data(using: .utf8)!
  /// print(data.md5hex) // → "5d41402abc4b2a76b9719d911017c592"
  /// ```
  public var md5hex: String {
    Insecure.MD5.hash(data: self)
      .map { String(format: "%02hhx", $0) }
      .joined()
  }

  /// Computes the MD5 hash of the data and returns it as a Base64-encoded string.
  ///
  /// This format is often used in HTTP headers (e.g., `Content-MD5`) or compact representations.
  ///
  /// Example:
  /// ```swift
  /// let data = "hello".data(using: .utf8)!
  /// print(data.md5base64) // → "XUFAKrxLKna5cZ2REBfFkg=="
  /// ```
  public var md5base64: String {
    let digest = Insecure.MD5.hash(data: self)
    return Data(digest).base64EncodedString()
  }
}
