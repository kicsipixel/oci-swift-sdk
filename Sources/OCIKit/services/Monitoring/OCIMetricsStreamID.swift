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

/// The in-process identity of one metric stream: what kind of instrument it is, its swift-metrics
/// label, and its dimensions.
///
/// This is the registry's key, so two `Counter("requests", ["host": "a"])` values created anywhere
/// in the process share a single handler and aggregate together. It deliberately mirrors — but is
/// not identical to — the service's notion of a metric stream (namespace + name + compartment +
/// resource group + dimensions): namespace, compartment and resource group are process-wide
/// configuration, so they cannot vary between two handlers and play no part in the identity.
struct OCIMetricsStreamID: Hashable, Sendable {
  /// The swift-metrics instrument a handler was created for.
  ///
  /// The kind is part of the identity because the same label may legitimately back both a counter
  /// and a timer, and because the per-step aggregation differs between them.
  enum Kind: String, Hashable, Sendable {
    /// A `Counter` — monotonically increasing, exported as a per-step delta.
    case counter
    /// A `Recorder(aggregate: true)` / `Summary` — exported as the step's samples.
    case recorder
    /// A `Gauge`, i.e. `Recorder(aggregate: false)` — exported as the last value set.
    case gauge
    /// A `Timer` — exported as the step's durations, in nanoseconds.
    case timer
  }

  /// The instrument this stream was created for.
  let kind: Kind
  /// The swift-metrics label, used as the metric `name` on the wire.
  let label: String
  /// The swift-metrics dimensions, before sanitization and before the configuration's common
  /// dimensions are merged in.
  let dimensions: [String: String]

  /// Creates a stream identity.
  ///
  /// - Parameters:
  ///   - kind: The instrument the handler was created for.
  ///   - label: The swift-metrics label.
  ///   - dimensions: The swift-metrics dimensions.
  init(kind: Kind, label: String, dimensions: [String: String]) {
    self.kind = kind
    self.label = label
    self.dimensions = dimensions
  }

  /// Creates a stream identity from swift-metrics' `(name, value)` tuple list.
  ///
  /// swift-metrics passes dimensions as an ordered array that may repeat a key; the map is built
  /// with last-one-wins so that two instruments whose dimensions differ only in order share a
  /// stream.
  ///
  /// - Parameters:
  ///   - kind: The instrument the handler was created for.
  ///   - label: The swift-metrics label.
  ///   - dimensions: The swift-metrics dimensions, as `(name, value)` tuples.
  init(kind: Kind, label: String, dimensions: [(String, String)]) {
    var map: [String: String] = [:]
    map.reserveCapacity(dimensions.count)
    for (key, value) in dimensions { map[key] = value }
    self.init(kind: kind, label: label, dimensions: map)
  }

  /// A stable, total ordering key.
  ///
  /// A registry snapshot is drained from a dictionary, whose iteration order is not stable across
  /// runs. Sorting on this key before chunking makes the composition of each ≤50-stream request
  /// deterministic, which keeps both the tests and the on-wire batching reproducible.
  var sortKey: String {
    let dimensions = dimensions.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
    return "\(label)\u{0}\(kind.rawValue)\u{0}\(dimensions)"
  }
}
