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

/// ObjectStorage related errors
public enum ObjectStorageError: Error {
  case missingRequiredParameter(String)
  case invalidURL(String)
  case invalidResponse(String)
  case invalidUTF8
  case jsonEncodingError(String)
  case jsonDecodingError(String)
  case objectLengthMismatch(Int, Int)
  case objectMD5Mismatch(String, String)
}

extension ObjectStorageError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .missingRequiredParameter(let param): return "Missing required parameter \(param)"
    case .invalidURL(let url): return "Provided URL is invalid: \(url)"
    case .invalidResponse(let response): return "API returned an invalid reponse: \(response)"
    case .invalidUTF8: return "Malformed UTF8 representation"
    case .jsonEncodingError(let errorString): return "JSON encoding error: \(errorString)"
    case .jsonDecodingError(let errorString): return "JSON decoding error: \(errorString)"
    case .objectLengthMismatch(let actual, let original): return "Downloaded object length \(actual) does not match the original length reported by Object Storage \(original)"
    case .objectMD5Mismatch(let actual, let original): return "Downloaded object MD5 \(actual) does not match the original MD5 reported by Object Storage \(original)"
    }
  }
}

/// Decode the error response body
public struct DataBody: Codable {
  let code: String
  let message: String
}
