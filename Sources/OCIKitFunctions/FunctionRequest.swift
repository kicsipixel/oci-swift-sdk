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

/// The input to a single function invocation.
///
/// The body is the raw invocation payload; for a plain invocation it is whatever
/// bytes the caller sent, and for an HTTP-triggered invocation
/// (``InvocationContext/isHTTPRequest``) it is the original HTTP request body.
public struct FunctionRequest: Sendable {
  /// The raw request body bytes (empty if the invocation had no body).
  public let body: Data

  /// The `Content-Type` of the body, if the caller supplied one.
  public let contentType: String?

  public init(body: Data, contentType: String? = nil) {
    self.body = body
    self.contentType = contentType
  }

  /// The body decoded as a UTF-8 string, or `nil` if it is not valid UTF-8.
  public var string: String? {
    String(data: body, encoding: .utf8)
  }

  /// Decodes the body as JSON into `type`.
  ///
  /// - Throws: A `DecodingError` if the body is not valid JSON for `type`.
  public func decode<T: Decodable>(_ type: T.Type, using decoder: JSONDecoder = JSONDecoder()) throws -> T {
    try decoder.decode(type, from: body)
  }
}
