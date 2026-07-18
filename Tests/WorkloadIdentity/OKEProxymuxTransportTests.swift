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
import NIOCore
import NIOHTTP1
import Testing

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@testable import OCIKitWorkloadIdentity

// Credential-free, network-free unit tests for the request/response conversions
// that adapt AsyncHTTPClient to OCIKit's HTTPClient seam. The actual TLS pinning
// is exercised end-to-end by the swift-oke example against a live OKE cluster.

struct OKEProxymuxTransportTests {
  @Test("makeClientRequest maps the method, URL, and headers")
  func mapsRequest() {
    var urlRequest = URLRequest(
      url: URL(string: "https://10.0.0.1:12250/resourcePrincipalSessionTokens")!)
    urlRequest.httpMethod = "POST"
    urlRequest.setValue("Bearer sa.jwt.token", forHTTPHeaderField: "Authorization")
    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-type")
    urlRequest.httpBody = Data(#"{"podKey":"x"}"#.utf8)

    let clientRequest = OKEProxymuxTransport.makeClientRequest(from: urlRequest)
    #expect(clientRequest.url == "https://10.0.0.1:12250/resourcePrincipalSessionTokens")
    #expect(clientRequest.method == .POST)
    #expect(clientRequest.headers.first(name: "Authorization") == "Bearer sa.jwt.token")
    #expect(clientRequest.headers.first(name: "Content-type") == "application/json")
  }

  @Test("mapMethod maps common verbs and falls back to RAW")
  func mapsMethods() {
    #expect(OKEProxymuxTransport.mapMethod("POST") == .POST)
    #expect(OKEProxymuxTransport.mapMethod("get") == .GET)
    #expect(OKEProxymuxTransport.mapMethod(nil) == .GET)
    #expect(OKEProxymuxTransport.mapMethod("PROPFIND") == .RAW(value: "PROPFIND"))
  }

  @Test("makeResponse builds an HTTPURLResponse with the status, headers, and body")
  func buildsResponse() {
    let url = URL(string: "https://10.0.0.1:12250/resourcePrincipalSessionTokens")!
    let (data, response) = OKEProxymuxTransport.makeResponse(
      url: url,
      status: 200,
      headers: [(name: "opc-request-id", value: "abc/def/ghi")],
      bodyData: Data("hello".utf8)
    )
    let http = response as? HTTPURLResponse
    #expect(http?.statusCode == 200)
    #expect(http?.url == url)
    #expect(http?.value(forHTTPHeaderField: "opc-request-id") == "abc/def/ghi")
    #expect(String(data: data, encoding: .utf8) == "hello")
  }

  @Test("makeResponse preserves a non-2xx status")
  func preservesErrorStatus() {
    let url = URL(string: "https://10.0.0.1:12250/x")!
    let (_, response) = OKEProxymuxTransport.makeResponse(
      url: url, status: 403, headers: [], bodyData: Data())
    #expect((response as? HTTPURLResponse)?.statusCode == 403)
  }

  @Test("caPinned constructs a transport without touching the network")
  func caPinnedProducesTransport() {
    // The AsyncHTTPClient is created lazily inside the closure, which only runs
    // when the transport is invoked, so building it must not connect or throw.
    _ = OKEProxymuxTransport.caPinned(caCertPath: "/nonexistent/ca.pem")
    _ = OKEProxymuxTransport.caPinned(caCertPath: "/nonexistent/ca.pem", verifyHostname: false)
  }
}
