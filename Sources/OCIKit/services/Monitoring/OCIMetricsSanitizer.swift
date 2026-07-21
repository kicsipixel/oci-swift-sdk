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

/// Coerces swift-metrics labels and dimensions into values the Monitoring ingestion API accepts.
///
/// swift-metrics puts no constraints on a metric's label or on its dimension keys and values —
/// PostMetricData does, and violating them costs the whole metric object a `400` (or a
/// `failedMetrics` entry inside a `200`). Rather than reject the application's data, the backend
/// coerces it: whitespace in a dimension key collapses to `_`, over-long strings are truncated,
/// and dimensions that cannot be salvaged (an empty key or an empty value) are dropped.
///
/// Every limit below is documented by the service and was live-verified against
/// `telemetry-ingestion.us-phoenix-1.oraclecloud.com`.
enum OCIMetricsSanitizer {
  /// Maximum length of a dimension key.
  static let maximumDimensionKeyLength = 256
  /// Maximum length of a dimension value.
  static let maximumDimensionValueLength = 512
  /// Maximum length of a metric name.
  static let maximumMetricNameLength = 255
  /// Maximum length of a metric namespace.
  static let maximumNamespaceLength = 256
  /// Maximum number of dimensions the service accepts on one metric object.
  static let maximumDimensionsPerMetric = 20

  /// Namespace prefixes reserved for Oracle's own metrics.
  static let reservedNamespacePrefixes = ["oci_", "oracle_"]

  /// Sanitizes a dimension key: runs of whitespace collapse to a single underscore and the result
  /// is truncated to ``maximumDimensionKeyLength``.
  ///
  /// - Parameter raw: The key as swift-metrics supplied it.
  /// - Returns: A whitespace-free, non-empty key, or `nil` if nothing usable remains.
  static func dimensionKey(_ raw: String) -> String? {
    let collapsed = raw.split(whereSeparator: \.isWhitespace).joined(separator: "_")
    guard !collapsed.isEmpty else { return nil }
    return String(collapsed.prefix(maximumDimensionKeyLength))
  }

  /// Sanitizes a dimension value: surrounding whitespace is trimmed and the result is truncated to
  /// ``maximumDimensionValueLength``.
  ///
  /// Interior whitespace is legal in a value and is preserved.
  ///
  /// - Parameter raw: The value as swift-metrics supplied it.
  /// - Returns: A non-empty value, or `nil` if nothing usable remains.
  static func dimensionValue(_ raw: String) -> String? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    return String(trimmed.prefix(maximumDimensionValueLength))
  }

  /// Sanitizes every entry of a dimension map, dropping the entries that cannot be salvaged.
  ///
  /// - Parameter raw: The dimensions as swift-metrics supplied them.
  /// - Returns: The sanitized dimensions. May be empty — the caller is responsible for
  ///   synthesizing a default dimension, since the service rejects an empty map.
  static func dimensions(_ raw: [String: String]) -> [String: String] {
    var sanitized: [String: String] = [:]
    sanitized.reserveCapacity(raw.count)
    for (key, value) in raw {
      guard let key = dimensionKey(key), let value = dimensionValue(value) else { continue }
      sanitized[key] = value
    }
    return sanitized
  }

  /// Caps a dimension map at ``maximumDimensionsPerMetric`` entries, keeping the
  /// lexicographically-first keys so the choice is deterministic across steps and processes.
  ///
  /// - Parameter dimensions: The sanitized dimensions.
  /// - Returns: At most 20 dimensions.
  static func capped(_ dimensions: [String: String]) -> [String: String] {
    guard dimensions.count > maximumDimensionsPerMetric else { return dimensions }
    let kept = dimensions.sorted { $0.key < $1.key }.prefix(maximumDimensionsPerMetric)
    return Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
  }

  /// Sanitizes a metric name by truncating it to ``maximumMetricNameLength``.
  ///
  /// - Parameter raw: The swift-metrics label.
  /// - Returns: A name the service accepts.
  static func metricName(_ raw: String) -> String {
    String(raw.prefix(maximumMetricNameLength))
  }

  /// Whether `namespace` satisfies the service's namespace rules.
  ///
  /// A namespace must match `^[A-Za-z][A-Za-z0-9_]*$`, be at most
  /// ``maximumNamespaceLength`` characters long, and must not use a reserved prefix.
  ///
  /// - Parameter namespace: The candidate namespace.
  /// - Returns: `true` when the service will accept it.
  static func isValidNamespace(_ namespace: String) -> Bool {
    guard !namespace.isEmpty, namespace.count <= maximumNamespaceLength else { return false }
    guard let first = namespace.first, first.isASCII, first.isLetter else { return false }
    guard namespace.allSatisfy({ $0 == "_" || ($0.isASCII && ($0.isLetter || $0.isNumber)) }) else { return false }
    let lowercased = namespace.lowercased()
    return !reservedNamespacePrefixes.contains { lowercased.hasPrefix($0) }
  }
}
