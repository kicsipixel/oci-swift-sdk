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
//
// Credential-free unit tests for issue #91 (OCIMetricsFactory): the registry's
// key type (OCIMetricsStreamID) and the registry itself — get-or-create
// identity, destroy()/orphan handling, and deterministic drain ordering. No
// ~/.oci/config, no network.
//

import Foundation
import Testing

@testable import OCIKit

// MARK: - OCIMetricsStreamID

struct OCIMetricsStreamIDTests {
  @Test("two ids with the same kind, label and dimensions are equal regardless of dimension insertion order")
  func equalityIgnoresDimensionOrder() {
    let a = OCIMetricsStreamID(kind: .counter, label: "requests", dimensions: ["host": "a", "region": "phx"])
    let b = OCIMetricsStreamID(kind: .counter, label: "requests", dimensions: ["region": "phx", "host": "a"])
    #expect(a == b)
    #expect(a.hashValue == b.hashValue)
  }

  @Test("kind is part of the identity: the same label and dimensions produce different ids for different kinds")
  func kindIsPartOfIdentity() {
    let counter = OCIMetricsStreamID(kind: .counter, label: "requests", dimensions: [:])
    let timer = OCIMetricsStreamID(kind: .timer, label: "requests", dimensions: [:])
    #expect(counter != timer)
  }

  @Test("the tuple-array initializer builds its dimension map last-key-wins")
  func tupleInitializerIsLastWins() {
    let id = OCIMetricsStreamID(kind: .recorder, label: "latency", dimensions: [("host", "a"), ("host", "b")])
    #expect(id.dimensions == ["host": "b"])
  }

  @Test("sortKey is stable across dimension insertion order")
  func sortKeyStableAcrossOrder() {
    let a = OCIMetricsStreamID(kind: .gauge, label: "queue_depth", dimensions: ["b": "2", "a": "1"])
    let b = OCIMetricsStreamID(kind: .gauge, label: "queue_depth", dimensions: ["a": "1", "b": "2"])
    #expect(a.sortKey == b.sortKey)
  }

  @Test("sortKey orders primarily by label")
  func sortKeyOrdersByLabel() {
    let a = OCIMetricsStreamID(kind: .counter, label: "a_metric", dimensions: [:])
    let b = OCIMetricsStreamID(kind: .counter, label: "b_metric", dimensions: [:])
    #expect(a.sortKey < b.sortKey)
  }
}

// MARK: - OCIMetricsRegistry

struct OCIMetricsRegistryTests {
  private static let compartmentId = "ocid1.compartment.oc1..EXAMPLE"

  private func makeRegistry(maximumBufferedStreams: Int = 500, maximumSamplesPerStream: Int = 1000) throws -> OCIMetricsRegistry {
    let configuration = try OCIMetricsConfiguration(
      namespace: "my_app",
      compartmentId: Self.compartmentId,
      maximumBufferedStreams: maximumBufferedStreams,
      maximumSamplesPerStream: maximumSamplesPerStream
    )
    return OCIMetricsRegistry(configuration: configuration)
  }

  @Test("counter(id:) returns the same handler instance on repeated lookups of the same id")
  func counterGetOrCreateIsIdentity() throws {
    let registry = try makeRegistry()
    let id = OCIMetricsStreamID(kind: .counter, label: "requests", dimensions: ["host": "a"])
    #expect(registry.counter(id: id) === registry.counter(id: id))
  }

  @Test("recorder(id:aggregate:) returns the same handler instance on repeated lookups of the same id")
  func recorderGetOrCreateIsIdentity() throws {
    let registry = try makeRegistry()
    let id = OCIMetricsStreamID(kind: .recorder, label: "latency", dimensions: [:])
    #expect(registry.recorder(id: id, aggregate: true) === registry.recorder(id: id, aggregate: true))
  }

  @Test("timer(id:) returns the same handler instance on repeated lookups of the same id")
  func timerGetOrCreateIsIdentity() throws {
    let registry = try makeRegistry()
    let id = OCIMetricsStreamID(kind: .timer, label: "latency", dimensions: [:])
    #expect(registry.timer(id: id) === registry.timer(id: id))
  }

  @Test("drain() reports nothing for a registry with only idle handlers")
  func drainSkipsIdleHandlers() throws {
    let registry = try makeRegistry()
    _ = registry.counter(id: OCIMetricsStreamID(kind: .counter, label: "never_touched", dimensions: [:]))
    let drained = registry.drain()
    #expect(drained.snapshots.isEmpty)
    #expect(drained.droppedSamples == 0)
  }

  @Test("drain() orders snapshots deterministically by stream sortKey")
  func drainOrdersBySortKey() throws {
    let registry = try makeRegistry()
    for label in ["charlie", "alpha", "bravo"] {
      registry.counter(id: OCIMetricsStreamID(kind: .counter, label: label, dimensions: [:])).increment(by: 1)
    }
    let drained = registry.drain()
    #expect(drained.snapshots.map(\.id.label) == ["alpha", "bravo", "charlie"])
  }

  @Test("drain() aggregates the dropped-sample tally across every handler")
  func drainAggregatesDroppedSamples() throws {
    let registry = try makeRegistry(maximumSamplesPerStream: 1)
    let handler = registry.recorder(id: OCIMetricsStreamID(kind: .recorder, label: "latency", dimensions: [:]), aggregate: true)
    handler.record(1.0)
    handler.record(2.0)  // exceeds the per-stream bound of 1 distinct value, dropped
    let drained = registry.drain()
    #expect(drained.droppedSamples == 1)
  }

  @Test("destroy() retains a handler's un-drained values as an orphan snapshot for the next drain")
  func destroyRetainsResidualValues() throws {
    let registry = try makeRegistry()
    let id = OCIMetricsStreamID(kind: .counter, label: "requests", dimensions: [:])
    let handler = registry.counter(id: id)
    handler.increment(by: 5)

    registry.destroy(handler)

    let drained = registry.drain()
    #expect(drained.snapshots.count == 1)
    #expect(drained.snapshots.first?.id == id)
    #expect(drained.snapshots.first?.samples.first?.value == 5)
  }

  @Test("destroy() removes the handler from the registry so a later lookup creates a fresh one")
  func destroyRemovesFromRegistry() throws {
    let registry = try makeRegistry()
    let id = OCIMetricsStreamID(kind: .counter, label: "requests", dimensions: [:])
    let original = registry.counter(id: id)
    registry.destroy(original)
    let replacement = registry.counter(id: id)
    #expect(original !== replacement)
  }

  @Test("destroying a handler that is no longer the one registered for its id leaves the active handler untouched")
  func destroyingStaleHandlerLeavesActiveHandlerRegistered() throws {
    let registry = try makeRegistry()
    let id = OCIMetricsStreamID(kind: .counter, label: "requests", dimensions: [:])
    let original = registry.counter(id: id)
    registry.destroy(original)  // unregisters `original`
    let replacement = registry.counter(id: id)  // registry now holds a new handler for `id`
    replacement.increment(by: 9)

    registry.destroy(original)  // double-destroy of the stale handler: must not evict `replacement`

    let drained = registry.drain()
    #expect(drained.snapshots.contains { $0.id == id && $0.samples.first?.value == 9 })
  }

  @Test("orphan snapshots are bounded by maximumBufferedStreams; the oldest are dropped first")
  func orphansAreBoundedAndOldestDroppedFirst() throws {
    let registry = try makeRegistry(maximumBufferedStreams: 2)
    for label in ["first", "second", "third"] {
      let handler = registry.counter(id: OCIMetricsStreamID(kind: .counter, label: label, dimensions: [:]))
      handler.increment(by: 1)
      registry.destroy(handler)
    }
    let drained = registry.drain()
    #expect(drained.snapshots.count == 2)
    #expect(Set(drained.snapshots.map(\.id.label)) == ["second", "third"])
  }

  @Test("drain() clears orphans so they are not reported a second time")
  func drainClearsOrphans() throws {
    let registry = try makeRegistry()
    let id = OCIMetricsStreamID(kind: .counter, label: "requests", dimensions: [:])
    let handler = registry.counter(id: id)
    handler.increment(by: 1)
    registry.destroy(handler)

    _ = registry.drain()
    let secondDrain = registry.drain()
    #expect(secondDrain.snapshots.isEmpty)
  }
}
