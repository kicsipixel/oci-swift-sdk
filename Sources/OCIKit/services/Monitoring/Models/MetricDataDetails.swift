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

/// A metric object and the raw data points posted for it.
///
/// Each value combination of ``namespace``, ``name``, ``compartmentId``, ``resourceGroup`` and
/// ``dimensions`` identifies one *metric stream*. A single ``PostMetricDataDetails`` request may
/// carry at most **50 unique metric streams**; the number of ``datapoints`` per stream is
/// effectively unbounded.
public struct MetricDataDetails: Codable, Sendable {
  /// The source service or application emitting the metric.
  ///
  /// Must match `^[a-z][a-z0-9_]*[a-z0-9]$` — **lower case only**, live-verified: `MyApp` is
  /// rejected — and must not start with the reserved `oci_` or `oracle_` prefixes. Maximum 256
  /// characters. Example: `ocikit_probe`.
  public let namespace: String
  /// The resource group to which the metric belongs.
  ///
  /// A resource group is a custom string provided as a filter. Must start with an alphabetical
  /// character, may contain only alphanumeric characters, periods, underscores, hyphens and
  /// dollar signs. Maximum 256 characters.
  public let resourceGroup: String?
  /// The OCID of the compartment to post the metric data to.
  ///
  /// This is the compartment the metric is billed and queried against, and the compartment the
  /// caller's `use metrics` policy must cover.
  public let compartmentId: String
  /// The name of the metric.
  ///
  /// Must match `^[a-zA-Z][a-zA-Z0-9_.$-]*[a-zA-Z0-9]$` (live-verified: a name containing a space
  /// or ending in `_` is rejected). Maximum 255 characters. Example: `latency_ms`.
  public let name: String
  /// Qualifiers provided in the metric definition, as a map of key/value pairs.
  ///
  /// - Important: **Must be non-empty** — an omitted or `{}` value is rejected with `400`
  ///   `"dimensions can not be null or empty"` (live-verified). A metric with no natural labels
  ///   still needs a synthesized dimension. 1–20 entries per metric; keys contain no whitespace
  ///   and are at most 256 characters; values are non-empty and at most 512 characters.
  public let dimensions: [String: String]
  /// Additional metadata for the metric, as a map of key/value pairs.
  ///
  /// Typically used for units and display names, e.g. `["unit": "ms", "displayName": "Latency"]`.
  /// Keys and values follow the same character limits as ``dimensions``.
  public let metadata: [String: String]?
  /// The metric values posted for this metric stream, with their timestamps.
  public let datapoints: [MonitoringDatapoint]

  /// Creates the metric object posted for one metric stream.
  ///
  /// - Parameters:
  ///   - namespace: The source service or application emitting the metric.
  ///   - resourceGroup: The optional resource group the metric belongs to.
  ///   - compartmentId: The OCID of the compartment to post the metric data to.
  ///   - name: The name of the metric.
  ///   - dimensions: The metric's qualifiers. Must contain 1–20 entries.
  ///   - metadata: Additional metadata such as units and display names.
  ///   - datapoints: The metric values and their timestamps.
  public init(
    namespace: String,
    resourceGroup: String? = nil,
    compartmentId: String,
    name: String,
    dimensions: [String: String],
    metadata: [String: String]? = nil,
    datapoints: [MonitoringDatapoint]
  ) {
    self.namespace = namespace
    self.resourceGroup = resourceGroup
    self.compartmentId = compartmentId
    self.name = name
    self.dimensions = dimensions
    self.metadata = metadata
    self.datapoints = datapoints
  }
}
