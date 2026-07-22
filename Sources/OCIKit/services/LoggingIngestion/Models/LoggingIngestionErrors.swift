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

/// Errors thrown by ``LoggingIngestClient``.
///
/// Errors are recorded in logs and also thrown as exceptions.
///
/// Log format:
/// `[Logging Ingestion function name]` error code (HTTPResponse.statusCode): error message
///
/// Example:
/// `[putLogs]` NotAuthorizedOrNotFound (404): Authorization failed or requested resource not found
///
/// Thrown error format (without the function name):
/// Error (HTTPResponse.statusCode): error message
///
/// Example:
/// Error (404): Authorization failed or requested resource not found
public enum LoggingIngestionError: Error, Sendable {
  /// The API returned an invalid or unexpected response.
  case invalidResponse(String)

  /// The constructed URL is invalid.
  case invalidURL(String)

  /// Failed to encode the request body to JSON.
  case jsonEncodingError(String)

  /// A required parameter was not provided.
  case missingRequiredParameter(String)

  /// The API returned an unexpected HTTP status code.
  case unexpectedStatusCode(Int, String)
}

extension LoggingIngestionError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .invalidResponse(let response):
      return "API returned an invalid response: \(response)"
    case .invalidURL(let url):
      return "Provided URL is invalid: \(url)"
    case .jsonEncodingError(let errorString):
      return "JSON encoding error: \(errorString)"
    case .missingRequiredParameter(let param):
      return "Missing required parameter: \(param)"
    case .unexpectedStatusCode(let code, let message):
      return "Error (\(code)): \(message)"
    }
  }
}
