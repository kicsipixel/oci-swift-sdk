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

/// A single metric value and the time it was observed.
///
/// The service name for this type is `Datapoint`; it is prefixed here because OCIKit ships as a
/// single module and `Datapoint` is too generic to claim module-wide.
///
/// - Important: For a data point to be accepted, its ``timestamp`` must be **less than two hours
///   in the past and less than ten minutes in the future**. The limit is enforced strictly:
///   out-of-window data points are rejected with
///   `"The datapoint timestamps must be between 2 hours ago and 10 minutes from now."`, either as
///   a per-metric entry in ``PostMetricDataResponseDetails/failedMetrics`` (default,
///   non-atomic batches) or as a `400` when every metric in the batch fails. Datapoints buffered
///   across an outage longer than two hours are permanently unpostable.
public struct MonitoringDatapoint: Codable, Sendable {
  /// The timestamp at which this value was observed.
  ///
  /// Encoded as an RFC3339 timestamp with millisecond precision, e.g. `2023-02-01T01:02:29.600Z`.
  public let timestamp: Date
  /// The numeric value of the metric at ``timestamp``.
  public let value: Double
  /// The number of occurrences of the associated value in the set of data.
  ///
  /// Default is `1`. Value must be greater than zero.
  public let count: Int?

  /// Creates a data point.
  ///
  /// - Parameters:
  ///   - timestamp: The time the value was observed. Must be within `(now - 2h, now + 10m)`.
  ///   - value: The numeric value of the metric.
  ///   - count: The number of occurrences of `value`. Defaults to `nil`, which the service
  ///     interprets as `1`.
  public init(timestamp: Date, value: Double, count: Int? = nil) {
    self.timestamp = timestamp
    self.value = value
    self.count = count
  }

  private enum CodingKeys: String, CodingKey {
    case timestamp, value, count
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let raw = try container.decode(String.self, forKey: .timestamp)
    guard let timestamp = Self.parseTimestamp(raw) else {
      throw DecodingError.dataCorruptedError(
        forKey: .timestamp,
        in: container,
        debugDescription: "Expected an RFC3339 timestamp, found \"\(raw)\"."
      )
    }
    self.timestamp = timestamp
    self.value = try container.decode(Double.self, forKey: .value)
    self.count = try container.decodeIfPresent(Int.self, forKey: .count)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(timestamp.toRFC3339(), forKey: .timestamp)
    try container.encode(value, forKey: .value)
    try container.encodeIfPresent(count, forKey: .count)
  }

  /// Parses an RFC3339 timestamp, tolerating a missing fractional-seconds component.
  ///
  /// The service echoes posted data points back inside ``FailedMetricRecord`` with millisecond
  /// precision, but a response must never fail to decode over a formatting detail — the whole
  /// point of reading the body is to learn *why* metrics were rejected.
  private static func parseTimestamp(_ string: String) -> Date? {
    if let date = Date.fromRFC3339(string) { return date }
    let plain = ISO8601DateFormatter()
    plain.formatOptions = [.withInternetDateTime]
    return plain.date(from: string)
  }
}
