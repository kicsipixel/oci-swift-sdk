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

/// The Zipkin B3 propagation headers the Functions platform injects on every
/// invocation of a traced function.
///
/// On a direct invoke only `X-B3-TraceId` and `X-B3-SpanId` are sent (64-bit hex);
/// the rest appear when the caller propagates a trace of its own.
enum B3Header {
  static let traceId = "X-B3-TraceId"
  static let spanId = "X-B3-SpanId"
  static let parentSpanId = "X-B3-ParentSpanId"
  static let sampled = "X-B3-Sampled"
  static let flags = "X-B3-Flags"
}

/// The environment variables the Functions platform injects when tracing is
/// enabled on the application and function.
enum TracingEnvironment {
  static let enabled = "OCI_TRACING_ENABLED"
  static let collectorURL = "OCI_TRACE_COLLECTOR_URL"
}

/// The distributed-tracing context of one invocation: the platform's per-container
/// tracing configuration combined with the per-invocation Zipkin B3 headers.
///
/// This mirrors `fdk-java`'s `OCITracingContext`. Enable tracing on the application
/// and the function (Console, CLI, or Terraform) and the platform injects
/// `OCI_TRACING_ENABLED` and `OCI_TRACE_COLLECTOR_URL` into the container plus
/// `X-B3-*` headers into every invocation; with tracing off, ``isEnabled`` is
/// `false` and every identifier is `nil`.
///
/// The FDK ships no tracer and takes no OpenTelemetry dependency — it only surfaces
/// what the platform sent, so a handler can feed any OTLP/HTTP exporter:
///
/// ```swift
/// try await FunctionRuntime.serve { context, request in
///   let tracing = context.tracing
///   if tracing.isEnabled, tracing.isSampled, let endpoint = tracing.collectorEndpoint {
///     // POST spans for tracing.traceId / tracing.spanId to endpoint.otlpTracesURL,
///     // authenticated with endpoint.dataKeyHeaderValue, named tracing.serviceName.
///   }
///   return .text("ok")
/// }
/// ```
///
/// B3 trace and span ids are 64-bit hex; W3C/OTLP trace ids are 128-bit, so
/// left-pad ``traceId`` with zeros when exporting.
public struct TracingContext: Sendable, Equatable {

  /// Whether the platform enabled tracing for this function (`OCI_TRACING_ENABLED`
  /// present and non-zero).
  public let isEnabled: Bool

  /// The raw APM collector URL (`OCI_TRACE_COLLECTOR_URL`), or `nil` when unset or
  /// empty.
  ///
  /// This is the APM domain's legacy Zipkin v2 endpoint with the data key embedded
  /// as a query item. Use ``collectorEndpoint`` for the OTLP/HTTP form of it.
  public let traceCollectorURL: String?

  /// The current trace id (`X-B3-TraceId`, 64-bit hex), or `nil` if the header is
  /// absent.
  public let traceId: String?

  /// The current span id (`X-B3-SpanId`, 64-bit hex), or `nil` if the header is
  /// absent. Spans the handler creates should treat this as their parent.
  public let spanId: String?

  /// The parent of ``spanId`` (`X-B3-ParentSpanId`), or `nil` if the header is
  /// absent — which it always is on a direct invoke.
  public let parentSpanId: String?

  /// Whether this trace is sampled (`X-B3-Sampled`).
  ///
  /// Per the FDK convention this is `true` whenever the header is absent, so a
  /// direct invoke — which carries no sampling decision — is sampled.
  public let isSampled: Bool

  /// The B3 debug flags (`X-B3-Flags`), or `nil` if the header is absent.
  public let flags: String?

  /// The conventional tracing service name for this function,
  /// `<app name>::<function name>` lowercased, or `nil` when the platform did not
  /// name the application and function.
  public let serviceName: String?

  /// The APM OTLP/HTTP traces endpoint and data key parsed out of
  /// ``traceCollectorURL``, or `nil` when tracing is off or the URL does not match
  /// the documented shape — in which case fall back to explicit configuration.
  public var collectorEndpoint: APMCollectorEndpoint? {
    guard let traceCollectorURL else { return nil }
    return APMCollectorEndpoint(collectorURL: traceCollectorURL)
  }

  /// Builds the tracing context from the container's configuration and one
  /// invocation's raw headers.
  ///
  /// - Parameters:
  ///   - runtime: The container-wide runtime context, read for the tracing
  ///     environment variables and the application/function names.
  ///   - headers: The raw invocation headers, read for the `X-B3-*` values — i.e.
  ///     ``InvocationContext/invocationHeaders``, *not* the decapsulated
  ///     ``InvocationContext/httpHeaders``.
  public init(runtime: RuntimeContext, headers: FunctionHeaders) {
    self.isEnabled = Self.parseEnabled(runtime.config[TracingEnvironment.enabled])

    let collectorURL = runtime.config[TracingEnvironment.collectorURL]
    self.traceCollectorURL = (collectorURL?.isEmpty == false) ? collectorURL : nil

    self.traceId = headers.first(B3Header.traceId)
    self.spanId = headers.first(B3Header.spanId)
    self.parentSpanId = headers.first(B3Header.parentSpanId)
    self.isSampled = Self.parseSampled(headers.first(B3Header.sampled))
    self.flags = headers.first(B3Header.flags)

    if let appName = runtime.appName, let functionName = runtime.functionName {
      self.serviceName = "\(appName.lowercased())::\(functionName.lowercased())"
    }
    else {
      self.serviceName = nil
    }
  }

  /// Reads `OCI_TRACING_ENABLED`: the platform sets `1`, and anything that is not a
  /// non-zero number (or the word `true`) leaves tracing off.
  private static func parseEnabled(_ value: String?) -> Bool {
    guard let value else { return false }
    if let number = Int(value) { return number != 0 }
    return value.caseInsensitiveCompare("true") == .orderedSame
  }

  /// Reads `X-B3-Sampled`: sampled unless the header explicitly says otherwise
  /// (`0` or `false`), matching the other FDKs.
  private static func parseSampled(_ value: String?) -> Bool {
    guard let value else { return true }
    if let number = Int(value) { return number != 0 }
    return value.caseInsensitiveCompare("false") != .orderedSame
  }
}
