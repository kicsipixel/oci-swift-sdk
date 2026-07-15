//===----------------------------------------------------------------------===//
//
// This source file is part of the oci-swift-sdk open source project
//
// Copyright (c) 2026 the oci-swift-sdk project authors
// Licensed under MIT License
//
// See LICENSE for license information
// See CONTRIBUTORS.md for the list of oci-swift-sdk project authors
//
// SPDX-License-Identifier: MIT License
//
//===----------------------------------------------------------------------===//

import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// An injectable HTTP transport used by service clients to perform requests.
///
/// The default ``live`` value performs real network I/O via `URLSession`. Tests
/// — and advanced consumers such as custom proxying, retry, or request logging —
/// can supply their own closure instead. Injecting a closure that returns canned
/// `(Data, HTTPURLResponse)` fixtures lets a client's request-building and
/// response-handling be exercised with no live OCI tenancy, credentials, or
/// network access.
public struct HTTPClient: Sendable {
  /// Performs `request` and returns the response bytes and metadata.
  public var data: @Sendable (_ request: URLRequest) async throws -> (Data, URLResponse)

  public init(data: @escaping @Sendable (_ request: URLRequest) async throws -> (Data, URLResponse)) {
    self.data = data
  }

  /// The production transport, backed by `URLSession.shared`.
  ///
  /// On Linux this resolves to the async shim in `URLSession+Linux.swift`, since
  /// swift-corelibs-foundation's `URLSession` lacks the native async method.
  public static let live = HTTPClient { request in
    try await URLSession.shared.data(for: request)
  }
}
