//===----------------------------------------------------------------------===//
//
// This source file is part of the oci-swift-sdk open source project
//
// Copyright (c) 2025 Szabolcs Toth and the oci-swift-sdk project authors
// Licensed under MIT License
//
// See LICENSE for license information
// See CONTRIBUTORS.md for the list of oci-swift-sdk project authors
//
// SPDX-License-Identifier: MIT License
//
//===----------------------------------------------------------------------===//

import Foundation

/// ObjectStorage-related errors.
/// Errors are recorded in logs and also thrown as exceptions.
///
/// Log format:
/// `[ObjectStorage function name]` error code (HTTPResponse.statusCode): error message
///
/// Example:
/// `[getObject]` error code (404): Object not found
///
/// Thrown error format (without the function name):
/// Error (HTTPResponse.statusCode): error message
///
/// Example:
/// Error (404): Object not found
public enum ObjectStorageError: Error {
  case invalidResponse(String)
  case invalidURL(String)
  case invalidUTF8
  case jsonDecodingError(String)
  case jsonEncodingError(String)
  case missingRequiredParameter(String)
  case objectLengthMismatch(Int, Int)
  case objectMD5Mismatch(String, String)
  case unexpectedStatusCode(Int, String)
}

extension ObjectStorageError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .invalidResponse(let response):
      return "API returned an invalid response: \(response)"
    case .invalidURL(let url):
      return "Provided URL is invalid: \(url)"
    case .invalidUTF8:
      return "Malformed UTF8 representation"
    case .jsonDecodingError(let errorString):
      return "JSON decoding error: \(errorString)"
    case .jsonEncodingError(let errorString):
      return "JSON encoding error: \(errorString)"
    case .missingRequiredParameter(let param):
      return "Missing required parameter \(param)"
    case .objectLengthMismatch(let actual, let original):
      return "Downloaded object length \(actual) does not match the original length reported by Object Storage \(original)"
    case .objectMD5Mismatch(let actual, let original):
      return "Downloaded object MD5 \(actual) does not match the original MD5 reported by Object Storage \(original)"
    case .unexpectedStatusCode(let code, let message):
      return "Error (\(code)): \(message)"
    }
  }
}

/// Decode the error response body
public struct DataBody: Codable {
  let code: String
  let message: String
}
