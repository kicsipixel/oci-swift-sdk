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

/// The result a function handler returns for a single invocation.
///
/// - For an **HTTP-triggered** invocation (``InvocationContext/isHTTPRequest``),
///   ``status`` and ``headers`` are conveyed back to the original HTTP client
///   (the FDK maps them onto `Fn-Http-Status` and `Fn-Http-H-*`).
/// - For a **plain** invocation, only ``body`` (and ``contentType``) reach the
///   caller; ``status`` and ``headers`` are ignored, because a plain invocation
///   has no HTTP response channel.
public struct FunctionResponse: Sendable {
  /// The HTTP status code returned to the client (HTTP-triggered invocations only).
  public var status: Int

  /// The response body bytes.
  public var body: Data

  /// The `Content-Type` of ``body``, if any. Passed through to the caller unprefixed.
  public var contentType: String?

  /// Additional response headers (HTTP-triggered invocations only).
  public var headers: [String: String]

  public init(status: Int = 200, body: Data = Data(), contentType: String? = nil, headers: [String: String] = [:]) {
    self.status = status
    self.body = body
    self.contentType = contentType
    self.headers = headers
  }

  /// A `text/plain; charset=utf-8` response from a string.
  public static func text(_ string: String, status: Int = 200) -> FunctionResponse {
    FunctionResponse(status: status, body: Data(string.utf8), contentType: "text/plain; charset=utf-8")
  }

  /// An `application/json` response from any `Encodable` value.
  public static func json<T: Encodable>(
    _ value: T,
    status: Int = 200,
    using encoder: JSONEncoder = JSONEncoder()
  ) throws -> FunctionResponse {
    FunctionResponse(status: status, body: try encoder.encode(value), contentType: "application/json")
  }

  /// A raw-bytes response with an optional content type.
  public static func data(_ data: Data, contentType: String? = nil, status: Int = 200) -> FunctionResponse {
    FunctionResponse(status: status, body: data, contentType: contentType)
  }

  /// An empty-body response.
  public static func empty(status: Int = 200) -> FunctionResponse {
    FunctionResponse(status: status)
  }
}
