//===----------------------------------------------------------------------===//
//
// This source file is part of the oci-swift-sdk open source project
//
// Copyright (c) 2026 Ilia Sazonov and the oci-swift-sdk project authors
// Licensed under MIT License
//
// See LICENSE for license information
// See CONTRIBUTORS.md for the list of oci-swift-sdk project authors
//
// SPDX-License-Identifier: MIT License
//
//===----------------------------------------------------------------------===//

import Foundation

/// A case-insensitive, order-preserving collection of HTTP header name/value pairs.
///
/// HTTP header names are case-insensitive on the wire, but Linux's Foundation and
/// SwiftNIO can present them with different casing than macOS. This view lets a
/// function handler look headers up without worrying about casing while preserving
/// the original names and order for iteration.
public struct FunctionHeaders: Sendable, Sequence {
  private var entries: [(name: String, value: String)]

  /// Creates an empty header collection.
  public init() {
    self.entries = []
  }

  /// Creates a header collection from a list of name/value pairs, preserving order.
  public init(_ pairs: [(name: String, value: String)]) {
    self.entries = pairs
  }

  /// The first value for `name` (case-insensitive), or `nil` if absent.
  public subscript(_ name: String) -> String? {
    first(name)
  }

  /// The first value for `name` (case-insensitive), or `nil` if absent.
  public func first(_ name: String) -> String? {
    entries.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
  }

  /// All values for `name` (case-insensitive), in order.
  public func all(_ name: String) -> [String] {
    entries.filter { $0.name.caseInsensitiveCompare(name) == .orderedSame }.map(\.value)
  }

  /// Appends a header, preserving any existing header with the same name.
  public mutating func add(name: String, value: String) {
    entries.append((name: name, value: value))
  }

  /// The original header names, in order (may contain duplicates).
  public var names: [String] {
    entries.map(\.name)
  }

  /// The underlying name/value pairs, in order.
  public var pairs: [(name: String, value: String)] {
    entries
  }

  /// The number of header entries.
  public var count: Int {
    entries.count
  }

  public func makeIterator() -> Array<(name: String, value: String)>.Iterator {
    entries.makeIterator()
  }
}
