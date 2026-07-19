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

/// The exact `Fn-*` header names used by the http-stream contract.
enum FnHeader {
  static let callID = "Fn-Call-Id"
  static let deadline = "Fn-Deadline"
  static let intent = "Fn-Intent"
  static let httpMethod = "Fn-Http-Method"
  static let httpRequestURL = "Fn-Http-Request-Url"
  static let httpStatus = "Fn-Http-Status"
  /// Prefix carrying an original client HTTP header, in both directions.
  static let httpHeaderPrefix = "Fn-Http-H-"
  static let fdkVersion = "Fn-Fdk-Version"
  static let fdkRuntime = "Fn-Fdk-Runtime"
  static let contentType = "Content-Type"
}

/// Identification stamped on every response (parity with the official FDKs).
enum FnFdk {
  static let version = "fdk-swift/0.1.0"
  static let runtime = "swift"
}

/// The value of `Fn-Intent` that marks an HTTP-gateway/trigger invocation.
private let intentHTTPRequest = "httprequest"

/// The framework-enforced deadline used when the platform sends no `Fn-Deadline`.
let defaultDeadlineSeconds: TimeInterval = 30

/// Pure, socket-free transforms implementing the Fn http-stream request/response
/// framing. Kept free of SwiftNIO so the contract can be unit-tested directly.
enum FnContract {

  /// Whether `Fn-Intent` marks an HTTP-gateway invocation (case-insensitive).
  static func isHTTPRequest(intentValue: String?) -> Bool {
    guard let intentValue else { return false }
    return intentValue.caseInsensitiveCompare(intentHTTPRequest) == .orderedSame
  }

  /// Parses an RFC3339 `Fn-Deadline` value, defaulting to `now + 30s` when absent
  /// or unparseable.
  static func parseDeadline(_ value: String?, now: Date) -> Date {
    guard let value, let parsed = rfc3339(value) else {
      return now.addingTimeInterval(defaultDeadlineSeconds)
    }
    return parsed
  }

  /// Parses an RFC3339 / ISO-8601 timestamp, tolerating fractional seconds.
  static func rfc3339(_ string: String) -> Date? {
    let withFraction = ISO8601DateFormatter()
    withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = withFraction.date(from: string) { return date }

    let plain = ISO8601DateFormatter()
    plain.formatOptions = [.withInternetDateTime]
    return plain.date(from: string)
  }

  /// Reconstructs the original client request headers from an HTTP-triggered
  /// invocation: strips the `Fn-Http-H-` prefix, keeps `Content-Type` unprefixed,
  /// and drops all other transport (`Fn-*`) headers.
  static func decapsulateRequestHeaders(_ incoming: [(name: String, value: String)]) -> FunctionHeaders {
    var headers = FunctionHeaders()
    let prefix = FnHeader.httpHeaderPrefix
    for (name, value) in incoming {
      if name.count > prefix.count,
        name.prefix(prefix.count).caseInsensitiveCompare(prefix) == .orderedSame
      {
        headers.add(name: String(name.dropFirst(prefix.count)), value: value)
      }
      else if name.caseInsensitiveCompare(FnHeader.contentType) == .orderedSame {
        headers.add(name: name, value: value)
      }
      // All other Fn-* / transport headers are intentionally dropped.
    }
    return headers
  }

  /// Builds the outgoing socket response headers for a handler result.
  ///
  /// For HTTP-triggered invocations the user status becomes `Fn-Http-Status` and
  /// user headers are re-prefixed as `Fn-Http-H-*` (except `Content-Type` and the
  /// `Fn-Fdk-*` identity headers). For plain invocations user headers pass through
  /// as-is. `Content-Type` and the `Fn-Fdk-*` identity headers are always added.
  ///
  /// `Content-Length` is **not** included here — the transport sets it from the body.
  static func encapsulateResponseHeaders(
    _ response: FunctionResponse,
    isHTTPRequest: Bool
  ) -> [(name: String, value: String)] {
    var out: [(name: String, value: String)] = []
    let prefix = FnHeader.httpHeaderPrefix

    // Content-Type may arrive via the dedicated property or the headers dict; the
    // property wins. It is always emitted unprefixed (never re-prefixed as
    // Fn-Http-H-*), so pull it out of the dict here and emit it once at the end.
    var contentType = response.contentType

    if isHTTPRequest {
      out.append((FnHeader.httpStatus, String(response.status)))
      for (name, value) in response.headers {
        if name.caseInsensitiveCompare(FnHeader.contentType) == .orderedSame {
          if contentType == nil { contentType = value }
          continue  // emitted unprefixed below
        }
        let isAlreadyPrefixed =
          name.count >= prefix.count
          && name.prefix(prefix.count).caseInsensitiveCompare(prefix) == .orderedSame
        let isFdk =
          name.caseInsensitiveCompare(FnHeader.fdkVersion) == .orderedSame
          || name.caseInsensitiveCompare(FnHeader.fdkRuntime) == .orderedSame
        if isAlreadyPrefixed || isFdk {
          out.append((name, value))
        }
        else {
          out.append((prefix + name, value))
        }
      }
    }
    else if contentType == nil {
      // Plain invocation: the body is returned raw, and per the contract only the
      // content type is meaningful. Other handler headers are intentionally ignored
      // — in particular framing headers (Content-Length, Transfer-Encoding) must not
      // be forwarded, since the transport sets Content-Length from the body.
      contentType =
        response.headers
        .first { $0.key.caseInsensitiveCompare(FnHeader.contentType) == .orderedSame }?.value
    }

    if let contentType {
      out.append((FnHeader.contentType, contentType))
    }
    out.append((FnHeader.fdkVersion, FnFdk.version))
    out.append((FnHeader.fdkRuntime, FnFdk.runtime))
    return out
  }
}
