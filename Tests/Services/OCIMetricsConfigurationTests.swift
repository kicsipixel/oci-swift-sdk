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
// Credential-free unit tests for issue #91 (OCIMetricsFactory), test group 1:
// dimension synthesis + sanitization, and the eager validation performed by
// OCIMetricsConfiguration.init. No ~/.oci/config, no network.
//

import Foundation
import Testing

@testable import OCIKit

// MARK: - OCIMetricsSanitizer

struct OCIMetricsSanitizerTests {
  @Test("dimensionKey collapses runs of whitespace to a single underscore")
  func dimensionKeyCollapsesWhitespace() {
    #expect(OCIMetricsSanitizer.dimensionKey("  bad key  ") == "bad_key")
    #expect(OCIMetricsSanitizer.dimensionKey("a\tb\nc") == "a_b_c")
  }

  @Test("dimensionKey returns nil for a key that is entirely whitespace")
  func dimensionKeyRejectsWhitespaceOnly() {
    #expect(OCIMetricsSanitizer.dimensionKey("   ") == nil)
    #expect(OCIMetricsSanitizer.dimensionKey("") == nil)
  }

  @Test("dimensionKey truncates to the 256-character service limit")
  func dimensionKeyTruncates() {
    let raw = String(repeating: "k", count: 300)
    let sanitized = OCIMetricsSanitizer.dimensionKey(raw)
    #expect(sanitized?.count == OCIMetricsSanitizer.maximumDimensionKeyLength)
  }

  @Test("dimensionValue trims surrounding whitespace but preserves interior whitespace")
  func dimensionValueTrims() {
    #expect(OCIMetricsSanitizer.dimensionValue("  v  ") == "v")
    #expect(OCIMetricsSanitizer.dimensionValue("  hello world  ") == "hello world")
  }

  @Test("dimensionValue returns nil for an empty or all-whitespace value")
  func dimensionValueRejectsEmpty() {
    #expect(OCIMetricsSanitizer.dimensionValue("") == nil)
    #expect(OCIMetricsSanitizer.dimensionValue("   ") == nil)
  }

  @Test("dimensionValue truncates to the 512-character service limit")
  func dimensionValueTruncates() {
    let raw = String(repeating: "v", count: 600)
    let sanitized = OCIMetricsSanitizer.dimensionValue(raw)
    #expect(sanitized?.count == OCIMetricsSanitizer.maximumDimensionValueLength)
    #expect(sanitized == String(repeating: "v", count: 512))
  }

  @Test("dimensions(_:) drops entries whose key or value cannot be salvaged")
  func dimensionsDropsUnsalvageableEntries() {
    let sanitized = OCIMetricsSanitizer.dimensions([
      "good": "value",
      "   ": "dropped-because-empty-key",
      "also-good": "   ",
    ])
    #expect(sanitized == ["good": "value"])
  }

  @Test("dimensions(_:) sanitizes surviving keys and values")
  func dimensionsSanitizesSurvivors() {
    let sanitized = OCIMetricsSanitizer.dimensions(["  bad key  ": "  v  "])
    #expect(sanitized == ["bad_key": "v"])
  }

  @Test("capped(_:) is a no-op at or under the 20-dimension limit")
  func cappedNoOpUnderLimit() {
    let dimensions = Dictionary(uniqueKeysWithValues: (0..<20).map { ("k\($0)", "v\($0)") })
    #expect(OCIMetricsSanitizer.capped(dimensions) == dimensions)
  }

  @Test("capped(_:) keeps the 20 lexicographically-first keys, deterministically")
  func cappedKeepsLexicographicallyFirstKeys() {
    let dimensions = Dictionary(uniqueKeysWithValues: (0..<25).map { ("k\(String(format: "%02d", $0))", "v\($0)") })
    let capped = OCIMetricsSanitizer.capped(dimensions)
    #expect(capped.count == 20)
    let expectedKeys = Set((0..<20).map { "k\(String(format: "%02d", $0))" })
    #expect(Set(capped.keys) == expectedKeys)
  }

  @Test("metricName truncates to the 255-character service limit")
  func metricNameTruncates() {
    let raw = String(repeating: "m", count: 300)
    #expect(OCIMetricsSanitizer.metricName(raw).count == OCIMetricsSanitizer.maximumMetricNameLength)
    #expect(OCIMetricsSanitizer.metricName("short") == "short")
  }

  @Test(
    "isValidNamespace accepts letters/digits/underscore starting with a letter, rejects reserved prefixes and malformed strings",
    arguments: [
      ("my_app", true),
      ("my_app_2", true),
      ("A", true),
      ("", false),
      ("1app", false),
      ("_app", false),
      ("my-app", false),
      ("my app", false),
      ("oci_app", false),
      ("oracle_app", false),
      ("OCI_app", false),  // case-insensitive prefix check
    ]
  )
  func namespaceValidation(namespace: String, expected: Bool) {
    #expect(OCIMetricsSanitizer.isValidNamespace(namespace) == expected)
  }

  @Test("isValidNamespace rejects a namespace over the 256-character limit")
  func namespaceValidationRejectsOverlong() {
    let namespace = "a" + String(repeating: "b", count: 256)
    #expect(OCIMetricsSanitizer.isValidNamespace(namespace) == false)
  }
}

// MARK: - OCIMetricsConfiguration

struct OCIMetricsConfigurationTests {
  private static let compartmentId = "ocid1.compartment.oc1..EXAMPLE"

  // MARK: Validation

  @Test("init throws invalidNamespace for a namespace the service would reject")
  func initThrowsInvalidNamespace() {
    do {
      _ = try OCIMetricsConfiguration(namespace: "oci_reserved", compartmentId: Self.compartmentId)
      Issue.record("expected OCIMetricsError.invalidNamespace")
    }
    catch OCIMetricsError.invalidNamespace(let namespace) {
      #expect(namespace == "oci_reserved")
    }
    catch {
      Issue.record("expected invalidNamespace, got \(error)")
    }
  }

  @Test("init throws missingCompartmentId for an empty or whitespace-only compartment id")
  func initThrowsMissingCompartmentId() {
    #expect(throws: OCIMetricsError.missingCompartmentId) {
      _ = try OCIMetricsConfiguration(namespace: "my_app", compartmentId: "   ")
    }
    #expect(throws: OCIMetricsError.missingCompartmentId) {
      _ = try OCIMetricsConfiguration(namespace: "my_app", compartmentId: "")
    }
  }

  @Test("init throws invalidStep for a zero or negative step")
  func initThrowsInvalidStep() {
    #expect(throws: OCIMetricsError.self) {
      _ = try OCIMetricsConfiguration(namespace: "my_app", compartmentId: Self.compartmentId, step: .zero)
    }
    #expect(throws: OCIMetricsError.self) {
      _ = try OCIMetricsConfiguration(namespace: "my_app", compartmentId: Self.compartmentId, step: .seconds(-1))
    }
  }

  @Test("init throws invalidBufferBound for a non-positive maximumBufferedStreams")
  func initThrowsInvalidBufferedStreamsBound() {
    do {
      _ = try OCIMetricsConfiguration(namespace: "my_app", compartmentId: Self.compartmentId, maximumBufferedStreams: 0)
      Issue.record("expected OCIMetricsError.invalidBufferBound")
    }
    catch OCIMetricsError.invalidBufferBound(let name, let value) {
      #expect(name == "maximumBufferedStreams")
      #expect(value == 0)
    }
    catch {
      Issue.record("expected invalidBufferBound, got \(error)")
    }
  }

  @Test("init throws invalidBufferBound for a non-positive maximumSamplesPerStream")
  func initThrowsInvalidSamplesPerStreamBound() {
    do {
      _ = try OCIMetricsConfiguration(namespace: "my_app", compartmentId: Self.compartmentId, maximumSamplesPerStream: -1)
      Issue.record("expected OCIMetricsError.invalidBufferBound")
    }
    catch OCIMetricsError.invalidBufferBound(let name, let value) {
      #expect(name == "maximumSamplesPerStream")
      #expect(value == -1)
    }
    catch {
      Issue.record("expected invalidBufferBound, got \(error)")
    }
  }

  @Test("a well-formed configuration validates and applies its defaults")
  func initAppliesDefaults() throws {
    let configuration = try OCIMetricsConfiguration(namespace: "my_app", compartmentId: Self.compartmentId)
    #expect(configuration.resourceGroup == nil)
    #expect(configuration.commonDimensions.isEmpty)
    #expect(configuration.defaultDimensionName == OCIMetricsConfiguration.fallbackDimensionName)
    #expect(configuration.step == .seconds(60))
    #expect(configuration.maximumBufferedStreams == 500)
    #expect(configuration.maximumSamplesPerStream == 1000)
  }

  @Test("an unsalvageable custom defaultDimensionName/Value falls back to the documented default")
  func initFallsBackForUnsalvageableDefaultDimension() throws {
    let configuration = try OCIMetricsConfiguration(
      namespace: "my_app",
      compartmentId: Self.compartmentId,
      defaultDimensionName: "   ",
      defaultDimensionValue: "   "
    )
    #expect(configuration.defaultDimensionName == OCIMetricsConfiguration.fallbackDimensionName)
    #expect(configuration.defaultDimensionValue == OCIMetricsConfiguration.fallbackDimensionValue)
  }

  @Test("commonDimensions are sanitized once at construction")
  func initSanitizesCommonDimensions() throws {
    let configuration = try OCIMetricsConfiguration(
      namespace: "my_app",
      compartmentId: Self.compartmentId,
      commonDimensions: ["  env  ": "  prod  ", "   ": "dropped"]
    )
    #expect(configuration.commonDimensions == ["env": "prod"])
  }

  // MARK: dimensions(for:) — wire dimension resolution

  @Test("dimensions(for:) synthesizes the default dimension when the instrument has none and common dimensions are empty")
  func dimensionsSynthesizesDefaultWhenEmpty() throws {
    let configuration = try OCIMetricsConfiguration(
      namespace: "my_app",
      compartmentId: Self.compartmentId,
      defaultDimensionName: "src",
      defaultDimensionValue: "test-host"
    )
    let id = OCIMetricsStreamID(kind: .counter, label: "requests", dimensions: [:])
    #expect(configuration.dimensions(for: id) == ["src": "test-host"])
  }

  @Test("dimensions(for:) does not synthesize the default dimension when the instrument has its own")
  func dimensionsDoesNotSynthesizeWhenPresent() throws {
    let configuration = try OCIMetricsConfiguration(namespace: "my_app", compartmentId: Self.compartmentId)
    let id = OCIMetricsStreamID(kind: .counter, label: "requests", dimensions: ["host": "worker-1"])
    #expect(configuration.dimensions(for: id) == ["host": "worker-1"])
  }

  @Test("dimensions(for:) sanitizes the instrument's own dimensions")
  func dimensionsSanitizesInstrumentDimensions() throws {
    let configuration = try OCIMetricsConfiguration(namespace: "my_app", compartmentId: Self.compartmentId)
    let id = OCIMetricsStreamID(kind: .counter, label: "requests", dimensions: ["  bad key  ": "  v  "])
    #expect(configuration.dimensions(for: id) == ["bad_key": "v"])
  }

  @Test("dimensions(for:) merges common dimensions over the instrument's own, and common wins on collision")
  func dimensionsCommonWinsOnCollision() throws {
    let configuration = try OCIMetricsConfiguration(
      namespace: "my_app",
      compartmentId: Self.compartmentId,
      commonDimensions: ["env": "prod", "service": "checkout"]
    )
    let id = OCIMetricsStreamID(kind: .counter, label: "requests", dimensions: ["env": "instrument-set-this", "host": "worker-1"])
    #expect(configuration.dimensions(for: id) == ["env": "prod", "service": "checkout", "host": "worker-1"])
  }

  @Test("dimensions(for:) caps the merged result at the service's 20-dimension limit")
  func dimensionsCapsAtServiceLimit() throws {
    let configuration = try OCIMetricsConfiguration(namespace: "my_app", compartmentId: Self.compartmentId)
    let ownDimensions = Dictionary(uniqueKeysWithValues: (0..<25).map { ("k\(String(format: "%02d", $0))", "v\($0)") })
    let id = OCIMetricsStreamID(kind: .counter, label: "requests", dimensions: ownDimensions)
    #expect(configuration.dimensions(for: id).count == OCIMetricsSanitizer.maximumDimensionsPerMetric)
  }

  // MARK: metricData(for:at:) — wire mapping

  @Test("metricData(for:at:) attaches unit metadata for a timer stream and no metadata otherwise")
  func metricDataAttachesTimerMetadataOnly() throws {
    let configuration = try OCIMetricsConfiguration(namespace: "my_app", compartmentId: Self.compartmentId)
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    let timerSnapshot = OCIMetricsStreamSnapshot(
      id: OCIMetricsStreamID(kind: .timer, label: "latency", dimensions: [:]),
      samples: [.init(value: 1_500_000)]
    )
    let timerMetric = configuration.metricData(for: timerSnapshot, at: now)
    #expect(timerMetric.metadata == ["unit": "ns"])

    let counterSnapshot = OCIMetricsStreamSnapshot(
      id: OCIMetricsStreamID(kind: .counter, label: "requests", dimensions: [:]),
      samples: [.init(value: 1)]
    )
    let counterMetric = configuration.metricData(for: counterSnapshot, at: now)
    #expect(counterMetric.metadata == nil)
  }

  @Test("metricData(for:at:) stamps every datapoint of the step with the same snapshot timestamp")
  func metricDataStampsAllDatapointsWithSnapshotTime() throws {
    let configuration = try OCIMetricsConfiguration(namespace: "my_app", compartmentId: Self.compartmentId)
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let snapshot = OCIMetricsStreamSnapshot(
      id: OCIMetricsStreamID(kind: .recorder, label: "latency", dimensions: [:]),
      samples: [.init(value: 10, count: 2), .init(value: 20, count: 1)]
    )
    let metric = configuration.metricData(for: snapshot, at: now)
    #expect(metric.datapoints.count == 2)
    #expect(metric.datapoints.allSatisfy { $0.timestamp == now })
    #expect(metric.datapoints.map(\.value) == [10, 20])
    #expect(metric.datapoints.map(\.count) == [2, 1])
  }

  @Test("metricData(for:at:) truncates an over-length label to the metric name limit")
  func metricDataTruncatesLongLabel() throws {
    let configuration = try OCIMetricsConfiguration(namespace: "my_app", compartmentId: Self.compartmentId)
    let longLabel = String(repeating: "m", count: 300)
    let snapshot = OCIMetricsStreamSnapshot(
      id: OCIMetricsStreamID(kind: .counter, label: longLabel, dimensions: [:]),
      samples: [.init(value: 1)]
    )
    let metric = configuration.metricData(for: snapshot, at: Date())
    #expect(metric.name.count == OCIMetricsSanitizer.maximumMetricNameLength)
  }
}
