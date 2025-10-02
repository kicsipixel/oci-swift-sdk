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
  static func fromRFC3339(_ string: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: string)
  }
}
