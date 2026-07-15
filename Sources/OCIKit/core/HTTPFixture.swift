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
//
// Record / replay support for `HTTPClient`. Capture a real OCI response once
// (through the SDK's own transport, so the fixture preserves exactly what the
// client sees — status, header casing, and body), commit it, and replay it in
// fast, credential-free, offline tests.
//

import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// A captured HTTP response (plus the request that produced it), serializable to
/// JSON so it can be committed and replayed in tests.
public struct HTTPFixture: Codable, Sendable {
  public struct Request: Codable, Sendable {
    public var method: String
    public var url: String
  }

  public var request: Request
  public var statusCode: Int
  /// Header name → value, exactly as `HTTPURLResponse.allHeaderFields` presented
  /// them on the capturing platform (this is where Darwin vs. Linux casing shows).
  public var headers: [String: String]
  /// Base64 so the fixture is safe for binary bodies (e.g. `getObject`).
  public var bodyBase64: String

  public var body: Data { Data(base64Encoded: bodyBase64) ?? Data() }

  public init(request: Request, statusCode: Int, headers: [String: String], body: Data) {
    self.request = request
    self.statusCode = statusCode
    self.headers = headers
    self.bodyBase64 = body.base64EncodedString()
  }

  /// Rebuilds the `(Data, HTTPURLResponse)` pair a client method expects.
  public func makeResponse() -> (Data, HTTPURLResponse) {
    let url = URL(string: request.url) ?? URL(string: "https://oci.invalid")!
    let response = HTTPURLResponse(
      url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: headers
    )!
    return (body, response)
  }

  public static func load(fromFile url: URL) throws -> HTTPFixture {
    try JSONDecoder().decode(HTTPFixture.self, from: Data(contentsOf: url))
  }

  public func save(to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(self).write(to: url)
  }
}

extension HTTPClient {
  /// Wraps `base` (default ``live``) so every response is also written to
  /// `directory` as `<METHOD>_<sanitized-path>.json`, then returned unchanged.
  ///
  /// Point a live client at real OCI with this transport to capture fixtures:
  /// ```swift
  /// let client = try ObjectStorageClient(
  ///   region: region, signer: apiKeySigner,
  ///   httpClient: .recording(into: fixturesDir))
  /// _ = try await client.getNamespace()   // writes GET_n.json
  /// ```
  public static func recording(into directory: URL, base: HTTPClient = .live) -> HTTPClient {
    HTTPClient { request in
      let (data, response) = try await base.data(request)
      if let http = response as? HTTPURLResponse {
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
          if let k = key as? String, let v = value as? String { headers[k] = v }
        }
        let fixture = HTTPFixture(
          request: .init(method: request.httpMethod ?? "GET", url: request.url?.absoluteString ?? ""),
          statusCode: http.statusCode,
          headers: headers,
          body: data
        )
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? fixture.save(to: directory.appending(path: fixtureFileName(for: request)))
      }
      return (data, response)
    }
  }

  /// A transport that ignores the request and always returns `fixture`.
  public static func replaying(_ fixture: HTTPFixture) -> HTTPClient {
    HTTPClient { _ in fixture.makeResponse() }
  }

  /// Loads a committed fixture file and replays it.
  public static func replaying(fromFile url: URL) throws -> HTTPClient {
    replaying(try HTTPFixture.load(fromFile: url))
  }
}

private func fixtureFileName(for request: URLRequest) -> String {
  let method = request.httpMethod ?? "GET"
  let segments = (request.url?.path ?? "").split(separator: "/").joined(separator: "_")
  return "\(method)_\(segments.isEmpty ? "root" : segments).json"
}
