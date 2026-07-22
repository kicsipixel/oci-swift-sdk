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

  /// The name published for a metric whose label contains nothing the service will accept.
  ///
  /// A swift-metrics label is unconstrained, so `Counter("λ")` is legal in the application and
  /// unusable on the wire. Publishing under a documented placeholder keeps the observation rather
  /// than losing it silently.
  static let fallbackMetricName = "unnamed_metric"

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

  /// Coerces a swift-metrics label into a metric name the service accepts.
  ///
  /// The service enforces `^[a-zA-Z][a-zA-Z0-9_.$-]*[a-zA-Z0-9]$` (live-verified: a name
  /// violating it comes back as a `failedMetrics` entry, which the exporter treats as a permanent
  /// rejection). swift-metrics constrains labels not at all, so `Counter("login attempts")` and
  /// `Timer("http/server/duration")` are both legal in the application and both unpostable —
  /// coercing them is the only way the observation survives.
  ///
  /// Illegal characters become `_`, leading characters are dropped until the name starts with a
  /// letter, the result is truncated to ``maximumMetricNameLength``, and trailing characters are
  /// dropped until the name ends with a letter or digit — which also repairs a truncation that
  /// happened to land on a `_`, `.`, `-` or `$`.
  ///
  /// - Parameter raw: The swift-metrics label.
  /// - Returns: A name the service accepts, or ``fallbackMetricName`` if nothing usable remains.
  static func metricName(_ raw: String) -> String {
    var name = String(raw.map { isMetricNameBodyCharacter($0) ? $0 : "_" })
    while let first = name.first, !isMetricNameStartCharacter(first) { name.removeFirst() }
    name = String(name.prefix(maximumMetricNameLength))
    while let last = name.last, !isMetricNameEndCharacter(last) { name.removeLast() }
    return name.isEmpty ? fallbackMetricName : name
  }

  /// Whether `character` may start a metric name: `[a-zA-Z]`.
  private static func isMetricNameStartCharacter(_ character: Character) -> Bool {
    character.isASCII && character.isLetter
  }

  /// Whether `character` may end a metric name: `[a-zA-Z0-9]`.
  private static func isMetricNameEndCharacter(_ character: Character) -> Bool {
    character.isASCII && (character.isLetter || character.isNumber)
  }

  /// Whether `character` may appear in the interior of a metric name: `[a-zA-Z0-9_.$-]`.
  private static func isMetricNameBodyCharacter(_ character: Character) -> Bool {
    isMetricNameEndCharacter(character) || (character.isASCII && "_.$-".contains(character))
  }

  /// Whether `namespace` satisfies the service's namespace rules.
  ///
  /// A namespace must match `^[a-z][a-z0-9_]*[a-z0-9]$` — **lower case only** (live-verified:
  /// `MyApp`, `ocikit_Probe` and `ocikit_probe_` are each rejected with
  /// `"namespace must match pattern ^[a-z][a-z0-9_]*[a-z0-9]$"`), be at most
  /// ``maximumNamespaceLength`` characters long, and must not use a reserved prefix. A single
  /// lowercase letter is accepted despite the pattern's two-character shape (live-verified).
  ///
  /// - Parameter namespace: The candidate namespace.
  /// - Returns: `true` when the service will accept it.
  static func isValidNamespace(_ namespace: String) -> Bool {
    guard !namespace.isEmpty, namespace.count <= maximumNamespaceLength else { return false }
    guard let first = namespace.first, isNamespaceStartCharacter(first) else { return false }
    guard let last = namespace.last, isNamespaceEndCharacter(last) else { return false }
    guard namespace.allSatisfy(isNamespaceBodyCharacter) else { return false }
    return !reservedNamespacePrefixes.contains { namespace.hasPrefix($0) }
  }

  /// Whether `character` may start a namespace: `[a-z]`.
  private static func isNamespaceStartCharacter(_ character: Character) -> Bool {
    character.isASCII && character.isLetter && character.isLowercase
  }

  /// Whether `character` may end a namespace: `[a-z0-9]`.
  private static func isNamespaceEndCharacter(_ character: Character) -> Bool {
    guard character.isASCII else { return false }
    return character.isNumber || (character.isLetter && character.isLowercase)
  }

  /// Whether `character` may appear in the interior of a namespace: `[a-z0-9_]`.
  private static func isNamespaceBodyCharacter(_ character: Character) -> Bool {
    character == "_" || isNamespaceEndCharacter(character)
  }
}
