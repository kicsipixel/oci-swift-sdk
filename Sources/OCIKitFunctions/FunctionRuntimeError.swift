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

/// Fatal errors raised while starting or running the FDK runtime.
///
/// These indicate a broken container contract (a missing or malformed
/// `FN_LISTENER`, an unsupported `FN_FORMAT`, or a socket that cannot be bound)
/// and are surfaced from ``FunctionRuntime/serve(logger:_:)`` so the process can
/// exit rather than silently accept no traffic.
public enum FunctionRuntimeError: Error, LocalizedError, Equatable {
  /// `FN_LISTENER` was not set in the environment.
  case missingListener
  /// `FN_LISTENER` was set to a value that is not a `unix:<path>` address.
  case invalidListener(String)
  /// `FN_FORMAT` was set to a value other than `http-stream` (or empty).
  case unsupportedFormat(String)
  /// The Unix domain socket could not be bound or prepared.
  case socketSetupFailed(String)

  public var errorDescription: String? {
    switch self {
    case .missingListener:
      return "FN_LISTENER is not set; this program must be run by the Fn/OCI Functions platform"
    case .invalidListener(let value):
      return "FN_LISTENER is not a valid unix socket address: \(value)"
    case .unsupportedFormat(let value):
      return "Unsupported FN_FORMAT '\(value)'; only 'http-stream' (or empty) is supported"
    case .socketSetupFailed(let message):
      return "Failed to set up the Fn listener socket: \(message)"
    }
  }
}
