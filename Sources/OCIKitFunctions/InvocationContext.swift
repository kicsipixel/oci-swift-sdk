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

/// Per-invocation context passed to a function handler.
///
/// Carries the Fn call metadata and, for HTTP-triggered invocations, the
/// decapsulated original HTTP request line and headers.
public struct InvocationContext: Sendable {
  /// The container-wide runtime context (config/env, warm state accessors).
  public let runtime: RuntimeContext

  /// The unique id of this invocation (`Fn-Call-Id`), if present.
  public let callID: String?

  /// The instant by which the handler must finish (`Fn-Deadline`), or
  /// `now + 30s` when the platform did not supply one. The FDK cancels the
  /// handler and returns `504` if this deadline is exceeded.
  public let deadline: Date

  /// `true` when this is an HTTP-gateway/trigger invocation (`Fn-Intent: httprequest`).
  ///
  /// When `true`, ``httpMethod``, ``requestURL`` and ``httpHeaders`` describe the
  /// original client HTTP request, and the handler's ``FunctionResponse/status``
  /// and ``FunctionResponse/headers`` are returned to that client.
  public let isHTTPRequest: Bool

  /// The original client HTTP method (`Fn-Http-Method`), for HTTP-triggered invocations.
  public let httpMethod: String?

  /// The original client request URL (`Fn-Http-Request-Url`), for HTTP-triggered invocations.
  public let requestURL: String?

  /// The original client request headers (with the `Fn-Http-H-` transport prefix
  /// stripped), for HTTP-triggered invocations. Empty for plain invocations.
  public let httpHeaders: FunctionHeaders

  public init(
    runtime: RuntimeContext,
    callID: String?,
    deadline: Date,
    isHTTPRequest: Bool,
    httpMethod: String? = nil,
    requestURL: String? = nil,
    httpHeaders: FunctionHeaders = FunctionHeaders()
  ) {
    self.runtime = runtime
    self.callID = callID
    self.deadline = deadline
    self.isHTTPRequest = isHTTPRequest
    self.httpMethod = httpMethod
    self.requestURL = requestURL
    self.httpHeaders = httpHeaders
  }

  /// The time remaining until the invocation ``deadline`` (negative if already past).
  public var remaining: TimeInterval {
    deadline.timeIntervalSinceNow
  }
}
