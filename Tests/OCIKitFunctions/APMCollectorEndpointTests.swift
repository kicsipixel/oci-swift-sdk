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
import Testing

@testable import OCIKitFunctions

/// Credential-free, socket-free unit tests for ``APMCollectorEndpoint``: parsing
/// the legacy Zipkin collector URL the Functions platform injects as
/// `OCI_TRACE_COLLECTOR_URL` into the OTLP/HTTP traces endpoint + data key an
/// exporter needs.
///
/// The host used throughout (`EXAMPLE.apm-agt.us-phoenix-1.oci.oraclecloud.com`)
/// and the data keys are placeholders — no real APM domain id or data key.
@Suite("APM collector URL parsing")
struct APMCollectorEndpointTests {

  private let host = "EXAMPLE.apm-agt.us-phoenix-1.oci.oraclecloud.com"

  // MARK: - public-span

  @Test("parses a public-span collector URL into the OTLP public traces endpoint")
  func publicSpan() throws {
    let url = "https://\(host)/20200101/observations/public-span?dataFormat=zipkin&dataFormatVersion=2&dataKey=examplePublicDataKey"
    let endpoint = try #require(APMCollectorEndpoint(collectorURL: url))
    #expect(endpoint.visibility == .publicSpan)
    #expect(endpoint.dataKey == "examplePublicDataKey")
    #expect(endpoint.dataKeyHeaderValue == "dataKey examplePublicDataKey")
    #expect(endpoint.otlpTracesURL.absoluteString == "https://\(host)/20200101/opentelemetry/public/v1/traces")
  }

  // MARK: - private-span

  @Test("parses a private-span collector URL into the OTLP private traces endpoint")
  func privateSpan() throws {
    let url = "https://\(host)/20200101/observations/private-span?dataFormat=zipkin&dataFormatVersion=2&dataKey=examplePrivateDataKey"
    let endpoint = try #require(APMCollectorEndpoint(collectorURL: url))
    #expect(endpoint.visibility == .privateSpan)
    #expect(endpoint.dataKey == "examplePrivateDataKey")
    #expect(endpoint.otlpTracesURL.absoluteString == "https://\(host)/20200101/opentelemetry/private/v1/traces")
  }

  @Test("public-span and private-span segments are matched case-insensitively")
  func caseInsensitiveSegments() throws {
    let url = "https://\(host)/20200101/Observations/Public-Span?dataKey=k"
    let endpoint = try #require(APMCollectorEndpoint(collectorURL: url))
    #expect(endpoint.visibility == .publicSpan)
  }

  // MARK: - failure modes

  @Test("returns nil when the dataKey query item is missing")
  func missingDataKey() {
    let url = "https://\(host)/20200101/observations/public-span?dataFormat=zipkin"
    #expect(APMCollectorEndpoint(collectorURL: url) == nil)
  }

  @Test("returns nil when the dataKey query item is present but empty")
  func emptyDataKey() {
    let url = "https://\(host)/20200101/observations/public-span?dataKey="
    #expect(APMCollectorEndpoint(collectorURL: url) == nil)
  }

  @Test("returns nil for a totally different URL shape")
  func unrelatedURLShape() {
    #expect(APMCollectorEndpoint(collectorURL: "https://example.com/some/other/api/v1/thing?dataKey=k") == nil)
    #expect(APMCollectorEndpoint(collectorURL: "https://example.com/") == nil)
  }

  @Test("returns nil when there is no observations segment at all")
  func missingObservationsSegment() {
    #expect(APMCollectorEndpoint(collectorURL: "https://\(host)/20200101/public-span?dataKey=k") == nil)
  }

  @Test("returns nil when observations is the first path segment (no version prefix)")
  func noVersionBeforeObservations() {
    #expect(APMCollectorEndpoint(collectorURL: "https://\(host)/observations/public-span?dataKey=k") == nil)
  }

  @Test("returns nil for an unknown visibility segment")
  func unknownVisibilitySegment() {
    #expect(APMCollectorEndpoint(collectorURL: "https://\(host)/20200101/observations/weird-span?dataKey=k") == nil)
  }

  @Test("returns nil when observations is the last path segment (no visibility follows)")
  func observationsWithNoFollowingSegment() {
    #expect(APMCollectorEndpoint(collectorURL: "https://\(host)/20200101/observations?dataKey=k") == nil)
  }

  @Test("returns nil for a relative URL with no host")
  func noHost() {
    #expect(APMCollectorEndpoint(collectorURL: "/20200101/observations/public-span?dataKey=k") == nil)
  }

  @Test("returns nil for a string URL(string:) itself cannot parse")
  func unparseableString() {
    #expect(APMCollectorEndpoint(collectorURL: "") == nil)
    #expect(APMCollectorEndpoint(collectorURL: "http://[::1") == nil)
  }

  @Test("returns nil for a syntactically valid but hostless/schemeless string")
  func hostlessString() {
    #expect(APMCollectorEndpoint(collectorURL: "not a url with spaces") == nil)
  }

  // MARK: - shape preservation

  @Test("a path prefix ahead of the version segment is preserved verbatim")
  func pathPrefixPreserved() throws {
    let url = "https://\(host)/some/prefix/20200101/observations/public-span?dataKey=k"
    let endpoint = try #require(APMCollectorEndpoint(collectorURL: url))
    #expect(endpoint.otlpTracesURL.absoluteString == "https://\(host)/some/prefix/20200101/opentelemetry/public/v1/traces")
  }

  @Test("a future API version segment is carried over rather than hard-coded")
  func apiVersionPreserved() throws {
    let url = "https://\(host)/20250601/observations/public-span?dataKey=k"
    let endpoint = try #require(APMCollectorEndpoint(collectorURL: url))
    #expect(endpoint.otlpTracesURL.absoluteString == "https://\(host)/20250601/opentelemetry/public/v1/traces")
  }

  // MARK: - query handling

  @Test("extra query parameters beyond dataFormat/dataFormatVersion/dataKey do not break parsing and are stripped")
  func extraQueryParametersAreStripped() throws {
    let url = "https://\(host)/20200101/observations/public-span?dataFormat=zipkin&dataFormatVersion=2&dataKey=k&extra=1&another=two"
    let endpoint = try #require(APMCollectorEndpoint(collectorURL: url))
    #expect(endpoint.dataKey == "k")
    #expect(endpoint.otlpTracesURL.query == nil)
    #expect(endpoint.otlpTracesURL.absoluteString == "https://\(host)/20200101/opentelemetry/public/v1/traces")
  }

  @Test("the dataKey query item is matched case-insensitively by name")
  func dataKeyNameCaseInsensitive() throws {
    let url = "https://\(host)/20200101/observations/public-span?DataKey=k"
    let endpoint = try #require(APMCollectorEndpoint(collectorURL: url))
    #expect(endpoint.dataKey == "k")
  }

  @Test("a percent-encoded dataKey value is percent-decoded")
  func dataKeyPercentDecoded() throws {
    let url = "https://\(host)/20200101/observations/public-span?dataKey=abc%2Fdef%3D"
    let endpoint = try #require(APMCollectorEndpoint(collectorURL: url))
    #expect(endpoint.dataKey == "abc/def=")
  }

  @Test("a fragment on the collector URL is stripped from the OTLP URL")
  func fragmentStripped() throws {
    let url = "https://\(host)/20200101/observations/public-span?dataKey=k#ignored"
    let endpoint = try #require(APMCollectorEndpoint(collectorURL: url))
    #expect(endpoint.otlpTracesURL.fragment == nil)
  }

  // MARK: - explicit configuration (the documented fallback)

  @Test("the explicit initializer composes the OTLP traces path onto an APM dataUploadEndpoint")
  func explicitDataUploadEndpoint() throws {
    let base = try #require(URL(string: "https://\(host)"))
    let endpoint = APMCollectorEndpoint(dataUploadEndpoint: base, dataKey: "explicitKey")
    #expect(endpoint.visibility == .publicSpan)
    #expect(endpoint.dataKey == "explicitKey")
    #expect(endpoint.dataKeyHeaderValue == "dataKey explicitKey")
    #expect(endpoint.otlpTracesURL.absoluteString == "https://\(host)/20200101/opentelemetry/public/v1/traces")
  }

  @Test("the explicit initializer honours a trailing slash, a private visibility, and a custom API version")
  func explicitDataUploadEndpointVariants() throws {
    let base = try #require(URL(string: "https://\(host)/"))
    let endpoint = APMCollectorEndpoint(
      dataUploadEndpoint: base,
      dataKey: "explicitPrivateKey",
      visibility: .privateSpan,
      apiVersion: "20250601"
    )
    #expect(endpoint.visibility == .privateSpan)
    #expect(endpoint.otlpTracesURL.absoluteString == "https://\(host)/20250601/opentelemetry/private/v1/traces")
  }

  @Test("the explicit initializer reproduces exactly what parsing the injected collector URL yields")
  func explicitInitializerMatchesParsedEndpoint() throws {
    let parsed = try #require(
      APMCollectorEndpoint(collectorURL: "https://\(host)/20200101/observations/public-span?dataKey=k")
    )
    let base = try #require(URL(string: "https://\(host)"))
    #expect(APMCollectorEndpoint(dataUploadEndpoint: base, dataKey: "k") == parsed)
  }

  @Test("an already-composed OTLP URL can be wrapped directly")
  func explicitOTLPTracesURL() throws {
    let url = try #require(URL(string: "https://\(host)/20200101/opentelemetry/public/v1/traces"))
    let endpoint = APMCollectorEndpoint(otlpTracesURL: url, dataKey: "k", visibility: .publicSpan)
    #expect(endpoint.otlpTracesURL == url)
    #expect(endpoint.dataKeyHeaderValue == "dataKey k")
  }

  // MARK: - init?(collectorURL: URL) parity

  @Test("the URL-typed initializer agrees with the String-typed initializer")
  func urlInitializerParity() throws {
    let string = "https://\(host)/20200101/observations/private-span?dataKey=k"
    let url = try #require(URL(string: string))
    let fromString = try #require(APMCollectorEndpoint(collectorURL: string))
    let fromURL = try #require(APMCollectorEndpoint(collectorURL: url))
    #expect(fromString == fromURL)
  }
}
