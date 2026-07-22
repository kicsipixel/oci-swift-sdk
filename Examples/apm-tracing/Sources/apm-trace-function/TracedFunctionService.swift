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

import APMTracing
import Logging
import OCIKitFunctions
import ServiceLifecycle
import Tracing

/// The function itself, wrapped as a `ServiceLifecycle` service so it runs alongside
/// the swift-otel exporter and shares its graceful shutdown.
///
/// Every invocation opens one span parented on the trace the platform started, so the
/// handler's work shows up in Trace Explorer underneath the platform's own
/// `function invocation` span rather than as an orphan trace.
struct TracedFunctionService: Service {

  /// The FDK's diagnostic logger, forwarded to `FunctionRuntime.serve`.
  let logger: Logger

  /// Serves invocations until cancelled.
  func run() async throws {
    try await FunctionRuntime.serve(logger: logger) { context, request in
      try await Self.handle(context, request)
    }
  }

  /// Handles one invocation inside a span parented on the platform's B3 context.
  private static func handle(
    _ context: InvocationContext,
    _ request: FunctionRequest
  ) async throws -> FunctionResponse {
    let tracing = context.tracing

    // The platform's B3 ids are 64-bit; `B3TraceContext` left-pads the trace id to the
    // 128 bits OpenTelemetry requires and hands back a ready-made parent context.
    // A `nil` here means tracing is off or the headers were absent — start a new trace
    // rather than dropping the span.
    let parent = B3TraceContext(
      traceID: tracing.traceId,
      spanID: tracing.spanId,
      isSampled: tracing.isSampled
    )

    return try await withSpan(
      "apm-trace-function invocation",
      context: parent?.serviceContext ?? .topLevel,
      ofKind: .server
    ) { span in
      span.attributes["faas.invocation_id"] = context.callID
      span.attributes["faas.trigger"] = context.isHTTPRequest ? "http" : "other"
      span.attributes["ocikit.example"] = "apm-trace-function"
      span.attributes["ocikit.b3.trace_id"] = tracing.traceId
      span.attributes["ocikit.b3.span_id"] = tracing.spanId

      try await withSpan("apm-trace-function work") { child in
        child.attributes["ocikit.step"] = "work"
        try await Task.sleep(for: .milliseconds(10))
      }

      // What the caller sees: the 128-bit trace id its 64-bit B3 id was padded into,
      // so the invocation can be looked up with
      // `oci apm-traces trace trace get --trace-key <trace id>`.
      var carrier: [String: String] = [:]
      InstrumentationSystem.instrument.inject(span.context, into: &carrier, using: HeaderDictionaryInjector())
      let body = FunctionInvocationSummary(
        b3TraceID: tracing.traceId,
        otelTraceparent: carrier["traceparent"],
        serviceName: tracing.serviceName,
        echo: request.string
      )
      return try FunctionResponse.json(body)
    }
  }
}
