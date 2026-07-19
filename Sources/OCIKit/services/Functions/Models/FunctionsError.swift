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

/// Errors thrown by ``FunctionsInvokeClient``.
///
/// The service error body is decoded into the shared ``DataBody`` type when
/// present, otherwise the raw response text is surfaced.
public enum FunctionsError: Error {
  case invalidResponse(String)
  case invalidURL(String)
  case missingRequiredParameter(String)
  case unexpectedStatusCode(Int, String)
}

extension FunctionsError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .invalidResponse(let response):
      return "API returned an invalid response: \(response)"
    case .invalidURL(let url):
      return "Provided URL is invalid: \(url)"
    case .missingRequiredParameter(let param):
      return "Missing required parameter \(param)"
    case .unexpectedStatusCode(let code, let message):
      return "Error (\(code)): \(message)"
    }
  }
}
