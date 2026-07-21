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

/// Errors thrown by ``MonitoringClient``.
///
/// Log format: `[Monitoring function name]` error code (HTTPResponse.statusCode): error message.
/// The service error body is decoded into the shared ``DataBody`` type.
///
/// - Note: A partially-rejected batch is **not** an error — the service reports it inside a `200`
///   via ``PostMetricDataResponseDetails/failedMetrics``. Only a request-level failure (all
///   metric objects invalid, more than 50 metric streams, auth, throttling) surfaces as
///   ``unexpectedStatusCode(_:_:)``.
public enum MonitoringError: Error, Sendable {
  /// The API returned an invalid or unexpected response.
  case invalidResponse(String)

  /// The constructed URL is invalid.
  case invalidURL(String)

  /// Failed to decode the JSON response.
  case jsonDecodingError(String)

  /// Failed to encode the JSON request body.
  case jsonEncodingError(String)

  /// A required parameter was not provided.
  case missingRequiredParameter(String)

  /// The API returned an unexpected HTTP status code.
  case unexpectedStatusCode(Int, String)
}

extension MonitoringError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .invalidResponse(let response):
      return "API returned an invalid response: \(response)"
    case .invalidURL(let url):
      return "Provided URL is invalid: \(url)"
    case .jsonDecodingError(let errorString):
      return "JSON decoding error: \(errorString)"
    case .jsonEncodingError(let errorString):
      return "JSON encoding error: \(errorString)"
    case .missingRequiredParameter(let param):
      return "Missing required parameter: \(param)"
    case .unexpectedStatusCode(let code, let message):
      return "Error (\(code)): \(message)"
    }
  }
}
