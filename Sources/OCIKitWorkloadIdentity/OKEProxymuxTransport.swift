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
//
// A CA-pinning ``OCIKit/HTTPClient`` transport for the OKE Workload Identity
// proxymux token exchange, built on AsyncHTTPClient + NIOSSL (BoringSSL).
//
// This is the piece `URLSession` cannot provide: it verifies the proxymux TLS
// certificate against a specific cluster-CA PEM file, **in-process**, on both
// Linux and Apple platforms, without Apple's `Security` framework and without
// installing anything into the OS trust store — exactly what the OCI Java,
// Python, and Go SDKs do. It lives in the opt-in `OCIKitWorkloadIdentity`
// product so non-OKE consumers never pull the swift-nio dependency graph.
//

import AsyncHTTPClient
import Foundation
import NIOCore
import NIOHTTP1
import NIOSSL
import OCIKit

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Builds ``OCIKit/HTTPClient`` transports that verify the OKE proxymux TLS
/// certificate against the in-cluster Kubernetes CA, pinned **in-process**.
public enum OKEProxymuxTransport {

  /// A transport that pins `caCertPath` as the sole trust anchor for the
  /// proxymux exchange.
  ///
  /// A short-lived AsyncHTTPClient is created (and shut down) per exchange; the
  /// exchange happens only at prime/refresh time, so the setup cost is negligible.
  ///
  /// - Parameters:
  ///   - caCertPath: PEM file to trust (the cluster CA, typically
  ///     `/var/run/secrets/kubernetes.io/serviceaccount/ca.crt`).
  ///   - verifyHostname: When `true` (default) the server hostname must match the
  ///     certificate SAN (like the Go/Python SDKs). Set `false` to validate only
  ///     the chain against the pinned CA (like the Java SDK) if the proxymux
  ///     certificate does not carry the API-server host in its SAN.
  ///   - timeout: Per-request timeout for the exchange.
  public static func caPinned(
    caCertPath: String,
    verifyHostname: Bool = true,
    timeout: TimeAmount = .seconds(30)
  ) -> OCIKit.HTTPClient {
    OCIKit.HTTPClient { request in
      var tls = TLSConfiguration.makeClientConfiguration()
      tls.trustRoots = .file(caCertPath)  // replace system roots with just the cluster CA
      if !verifyHostname {
        tls.certificateVerification = .noHostnameVerification
      }
      let client = AsyncHTTPClient.HTTPClient(
        eventLoopGroupProvider: .singleton,
        configuration: .init(tlsConfiguration: tls)
      )
      do {
        let result = try await perform(request, using: client, timeout: timeout)
        try? await client.shutdown()  // best-effort; don't fail a successful exchange
        return result
      }
      catch {
        try? await client.shutdown()
        throw error
      }
    }
  }

  // MARK: - Conversions (internal, hermetically testable)

  /// Executes `request` on `client` and adapts the result to `(Data, URLResponse)`.
  static func perform(
    _ request: URLRequest,
    using client: AsyncHTTPClient.HTTPClient,
    timeout: TimeAmount,
    maxResponseBytes: Int = 1 << 20
  ) async throws -> (Data, URLResponse) {
    let response = try await client.execute(makeClientRequest(from: request), timeout: timeout)
    let buffer = try await response.body.collect(upTo: maxResponseBytes)
    let url = request.url ?? URL(string: "https://proxymux")!
    return makeResponse(
      url: url,
      status: Int(response.status.code),
      headers: response.headers.map { (name: $0.name, value: $0.value) },
      bodyData: Data(buffer.readableBytesView)
    )
  }

  /// Converts a `URLRequest` into an AsyncHTTPClient request.
  static func makeClientRequest(from urlRequest: URLRequest) -> HTTPClientRequest {
    var clientRequest = HTTPClientRequest(url: urlRequest.url?.absoluteString ?? "")
    clientRequest.method = mapMethod(urlRequest.httpMethod)
    for (name, value) in urlRequest.allHTTPHeaderFields ?? [:] {
      clientRequest.headers.add(name: name, value: value)
    }
    if let body = urlRequest.httpBody {
      clientRequest.body = .bytes(ByteBuffer(bytes: body))
    }
    return clientRequest
  }

  /// Builds the `(Data, HTTPURLResponse)` pair the ``OCIKit/HTTPClient`` seam expects.
  static func makeResponse(
    url: URL,
    status: Int,
    headers: [(name: String, value: String)],
    bodyData: Data
  ) -> (Data, URLResponse) {
    var fields: [String: String] = [:]
    for header in headers { fields[header.name] = header.value }
    let response =
      HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: fields)
      ?? HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
    return (bodyData, response)
  }

  /// Maps an HTTP method string to NIO's `HTTPMethod`.
  static func mapMethod(_ method: String?) -> NIOHTTP1.HTTPMethod {
    switch method?.uppercased() {
    case "GET": return .GET
    case "POST": return .POST
    case "PUT": return .PUT
    case "PATCH": return .PATCH
    case "DELETE": return .DELETE
    case "HEAD": return .HEAD
    case .some(let other): return .RAW(value: other)
    case .none: return .GET
    }
  }
}
