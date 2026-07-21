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

/// Credential-free, socket-free unit tests for ``TracingContext``: construction
/// from the `OCI_TRACING_ENABLED` / `OCI_TRACE_COLLECTOR_URL` environment values
/// and the per-invocation `X-B3-*` headers the Functions platform injects.
@Suite("Functions tracing context")
struct TracingContextTests {

  // MARK: - isEnabled

  @Test("isEnabled is true for OCI_TRACING_ENABLED=1")
  func enabledNumericOne() {
    let context = TracingContext(runtime: runtime(["OCI_TRACING_ENABLED": "1"]), headers: FunctionHeaders())
    #expect(context.isEnabled)
  }

  @Test("isEnabled is false for OCI_TRACING_ENABLED=0")
  func enabledNumericZero() {
    let context = TracingContext(runtime: runtime(["OCI_TRACING_ENABLED": "0"]), headers: FunctionHeaders())
    #expect(!context.isEnabled)
  }

  @Test("isEnabled accepts the word true, case-insensitively")
  func enabledWordTrue() {
    let context = TracingContext(runtime: runtime(["OCI_TRACING_ENABLED": "TRUE"]), headers: FunctionHeaders())
    #expect(context.isEnabled)
  }

  @Test("isEnabled is false when OCI_TRACING_ENABLED is absent")
  func enabledAbsent() {
    let context = TracingContext(runtime: runtime([:]), headers: FunctionHeaders())
    #expect(!context.isEnabled)
  }

  @Test("isEnabled is false for a non-numeric, non-true value")
  func enabledGarbage() {
    let context = TracingContext(runtime: runtime(["OCI_TRACING_ENABLED": "yes"]), headers: FunctionHeaders())
    #expect(!context.isEnabled)
  }

  // MARK: - traceCollectorURL

  @Test("traceCollectorURL is nil when OCI_TRACE_COLLECTOR_URL is unset")
  func collectorURLUnset() {
    let context = TracingContext(runtime: runtime([:]), headers: FunctionHeaders())
    #expect(context.traceCollectorURL == nil)
  }

  @Test("traceCollectorURL is nil when OCI_TRACE_COLLECTOR_URL is empty")
  func collectorURLEmpty() {
    let context = TracingContext(runtime: runtime(["OCI_TRACE_COLLECTOR_URL": ""]), headers: FunctionHeaders())
    #expect(context.traceCollectorURL == nil)
  }

  @Test("traceCollectorURL surfaces the raw configured value verbatim")
  func collectorURLPresent() {
    let url = "https://EXAMPLE.apm-agt.us-phoenix-1.oci.oraclecloud.com/20200101/observations/public-span?dataKey=k"
    let context = TracingContext(runtime: runtime(["OCI_TRACE_COLLECTOR_URL": url]), headers: FunctionHeaders())
    #expect(context.traceCollectorURL == url)
  }

  // MARK: - B3 headers: ids

  @Test("traceId and spanId are read from X-B3-TraceId / X-B3-SpanId")
  func idsFromHeaders() {
    let headers = FunctionHeaders([
      ("X-B3-TraceId", "463ac35c9f6413ad48485a3953bb6124"),
      ("X-B3-SpanId", "a2fb4a1d1a96d312"),
    ])
    let context = TracingContext(runtime: runtime([:]), headers: headers)
    #expect(context.traceId == "463ac35c9f6413ad48485a3953bb6124")
    #expect(context.spanId == "a2fb4a1d1a96d312")
  }

  @Test("traceId and spanId are nil when their headers are absent")
  func idsAbsent() {
    let context = TracingContext(runtime: runtime([:]), headers: FunctionHeaders())
    #expect(context.traceId == nil)
    #expect(context.spanId == nil)
  }

  @Test("parentSpanId is nil on a direct invoke, which carries no X-B3-ParentSpanId")
  func parentSpanIdAbsentOnDirectInvoke() {
    let headers = FunctionHeaders([
      ("X-B3-TraceId", "463ac35c9f6413ad48485a3953bb6124"),
      ("X-B3-SpanId", "a2fb4a1d1a96d312"),
    ])
    let context = TracingContext(runtime: runtime([:]), headers: headers)
    #expect(context.parentSpanId == nil)
  }

  @Test("parentSpanId is read from X-B3-ParentSpanId when a caller propagates a trace")
  func parentSpanIdPresent() {
    let headers = FunctionHeaders([("X-B3-ParentSpanId", "05e3ac9a4f6e3b90")])
    let context = TracingContext(runtime: runtime([:]), headers: headers)
    #expect(context.parentSpanId == "05e3ac9a4f6e3b90")
  }

  @Test("flags is read from X-B3-Flags, nil when absent")
  func flagsHeader() {
    let present = TracingContext(runtime: runtime([:]), headers: FunctionHeaders([("X-B3-Flags", "1")]))
    #expect(present.flags == "1")
    let absent = TracingContext(runtime: runtime([:]), headers: FunctionHeaders())
    #expect(absent.flags == nil)
  }

  // MARK: - isSampled

  @Test("isSampled defaults to true when X-B3-Sampled is absent (direct-invoke convention)")
  func sampledDefaultsTrue() {
    let context = TracingContext(runtime: runtime([:]), headers: FunctionHeaders())
    #expect(context.isSampled)
  }

  @Test("isSampled is false for X-B3-Sampled: 0")
  func sampledZero() {
    let headers = FunctionHeaders([("X-B3-Sampled", "0")])
    #expect(!TracingContext(runtime: runtime([:]), headers: headers).isSampled)
  }

  @Test("isSampled is false for X-B3-Sampled: false, case-insensitively")
  func sampledFalseWord() {
    let headers = FunctionHeaders([("X-B3-Sampled", "FALSE")])
    #expect(!TracingContext(runtime: runtime([:]), headers: headers).isSampled)
  }

  @Test("isSampled is true for X-B3-Sampled: 1")
  func sampledOne() {
    let headers = FunctionHeaders([("X-B3-Sampled", "1")])
    #expect(TracingContext(runtime: runtime([:]), headers: headers).isSampled)
  }

  @Test("isSampled is true for an unparseable X-B3-Sampled value")
  func sampledGarbage() {
    let headers = FunctionHeaders([("X-B3-Sampled", "maybe")])
    #expect(TracingContext(runtime: runtime([:]), headers: headers).isSampled)
  }

  // MARK: - Case-insensitive header lookup

  @Test("X-B3-* headers are matched case-insensitively, as the wire may present them")
  func caseInsensitiveHeaderLookup() {
    let headers = FunctionHeaders([
      ("x-b3-traceid", "463ac35c9f6413ad48485a3953bb6124"),
      ("X-B3-SPANID", "a2fb4a1d1a96d312"),
      ("x-B3-Sampled", "0"),
    ])
    let context = TracingContext(runtime: runtime([:]), headers: headers)
    #expect(context.traceId == "463ac35c9f6413ad48485a3953bb6124")
    #expect(context.spanId == "a2fb4a1d1a96d312")
    #expect(!context.isSampled)
  }

  // MARK: - serviceName

  @Test("serviceName is <app>::<function>, lowercased, when both are configured")
  func serviceNamePresent() {
    let context = TracingContext(
      runtime: runtime(["FN_APP_NAME": "MyApp", "FN_FN_NAME": "MyFunction"]),
      headers: FunctionHeaders()
    )
    #expect(context.serviceName == "myapp::myfunction")
  }

  @Test("serviceName is nil when FN_APP_NAME is missing")
  func serviceNameMissingAppName() {
    let context = TracingContext(runtime: runtime(["FN_FN_NAME": "MyFunction"]), headers: FunctionHeaders())
    #expect(context.serviceName == nil)
  }

  @Test("serviceName is nil when FN_FN_NAME is missing")
  func serviceNameMissingFunctionName() {
    let context = TracingContext(runtime: runtime(["FN_APP_NAME": "MyApp"]), headers: FunctionHeaders())
    #expect(context.serviceName == nil)
  }

  // MARK: - collectorEndpoint delegation

  @Test("collectorEndpoint is nil when tracing is off / traceCollectorURL is unset")
  func collectorEndpointNilWhenUnset() {
    let context = TracingContext(runtime: runtime([:]), headers: FunctionHeaders())
    #expect(context.collectorEndpoint == nil)
  }

  @Test("collectorEndpoint parses a valid public-span traceCollectorURL")
  func collectorEndpointParsesValidURL() throws {
    let url =
      "https://EXAMPLE.apm-agt.us-phoenix-1.oci.oraclecloud.com/20200101/observations/public-span"
      + "?dataFormat=zipkin&dataFormatVersion=2&dataKey=examplePublicDataKey"
    let context = TracingContext(runtime: runtime(["OCI_TRACE_COLLECTOR_URL": url]), headers: FunctionHeaders())
    let endpoint = try #require(context.collectorEndpoint)
    #expect(endpoint.visibility == .publicSpan)
    #expect(endpoint.dataKey == "examplePublicDataKey")
    #expect(
      endpoint.otlpTracesURL.absoluteString
        == "https://EXAMPLE.apm-agt.us-phoenix-1.oci.oraclecloud.com/20200101/opentelemetry/public/v1/traces"
    )
  }

  @Test("collectorEndpoint is nil when traceCollectorURL does not match the documented shape")
  func collectorEndpointNilForUnrecognizedURL() {
    let context = TracingContext(
      runtime: runtime(["OCI_TRACE_COLLECTOR_URL": "https://example.com/totally/unrelated"]),
      headers: FunctionHeaders()
    )
    #expect(context.collectorEndpoint == nil)
  }

  // MARK: - Helpers

  private func runtime(_ config: [String: String]) -> RuntimeContext {
    RuntimeContext(config: config)
  }
}
