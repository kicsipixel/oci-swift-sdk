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
import Logging

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Client for the OCI Functions **invoke** endpoint (API version `20181201`).
///
/// Use this to call a deployed function synchronously (`sync`) or fire-and-forget
/// (`detached`) from any Swift program — e.g. a service running on OKE, a Container
/// Instance, or a Compute VM. It signs the request with the injected ``Signer``
/// (API key, instance principal, resource principal, …), so the caller only needs
/// IAM permission to invoke the function.
///
/// Because each function is reached through its **own** invoke endpoint, construct
/// the client with the function's `invokeEndpoint` (obtained from the OCI Console,
/// Terraform, or `GetFunction`), not a regional endpoint. Function lifecycle
/// management is deliberately not part of this SDK.
///
/// The request and response bodies are opaque bytes (the platform limit is ~6 MB
/// each); this client does not assume JSON.
///
/// ## Example
/// ```swift
/// let signer = try InstancePrincipalSigner.fromMetadata()
/// let client = try FunctionsInvokeClient(
///   invokeEndpoint: "https://xxxxxxxx.us-ashburn-1.functions.oci.oraclecloud.com",
///   signer: signer
/// )
/// let output = try await client.invokeFunction(
///   functionId: "ocid1.fnfunc.oc1.iad.aaaa...",
///   body: Data(#"{"name":"world"}"#.utf8),
///   contentType: "application/json"
/// )
/// logger.info("function said: \(String(decoding: output, as: UTF8.self))")
/// ```
public struct FunctionsInvokeClient: Sendable {
  let endpoint: URL
  let retryConfig: RetryConfig?
  let signer: Signer
  let logger: Logger
  let httpClient: HTTPClient

  // MARK: - Initialization

  /// Initializes the Functions invoke client.
  ///
  /// - Parameters:
  ///   - invokeEndpoint: The function's own invoke endpoint URL (the `invokeEndpoint`
  ///     field of the `Function` resource, e.g.
  ///     `https://xxxxxxxx.us-ashburn-1.functions.oci.oraclecloud.com`).
  ///   - signer: A signer used to authenticate requests.
  ///   - retryConfig: The retry configuration applied to every invocation. `nil`
  ///     (the default) disables retries. Invocations are **not** idempotent, so
  ///     enable retries only when your function tolerates duplicate delivery.
  ///   - logger: Optional logger.
  ///   - httpClient: The HTTP transport used to perform requests. Defaults to
  ///     ``HTTPClient/live`` (real `URLSession` I/O); tests can inject a recording
  ///     or replaying transport.
  /// - Throws: ``FunctionsError/invalidURL(_:)`` if `invokeEndpoint` cannot be parsed.
  public init(
    invokeEndpoint: String,
    signer: Signer,
    retryConfig: RetryConfig? = nil,
    logger: Logger = Logger(label: "FunctionsInvokeClient"),
    httpClient: HTTPClient = .live
  ) throws {
    guard let url = URL(string: invokeEndpoint), url.scheme != nil, url.host != nil else {
      throw FunctionsError.invalidURL("Invalid invoke endpoint: \(invokeEndpoint)")
    }
    self.endpoint = url
    self.signer = signer
    self.retryConfig = retryConfig
    self.logger = logger
    self.httpClient = httpClient
  }

  // MARK: - Invoke

  /// Invokes a function and returns its raw response bytes.
  ///
  /// - Parameters:
  ///   - functionId: The OCID of the function to invoke.
  ///   - body: The invocation payload (default empty). The platform limit is ~6 MB.
  ///   - contentType: The `Content-Type` describing `body`. This is signed and is
  ///     forwarded to the function, so set it to match your payload (defaults to
  ///     `application/octet-stream`; pass `application/json` for JSON input).
  ///   - invokeType: `sync` (wait for the result, the platform default) or
  ///     `detached` (return once processing begins).
  ///   - intent: Optional `fn-intent` hint for the receiving FDK.
  ///   - isDryRun: When `true`, validates the request without executing the function.
  ///   - opcRequestId: Optional client-supplied request id for tracing.
  /// - Returns: The function's raw output bytes. For `detached` invocations the
  ///   body is typically empty.
  /// - Throws: ``FunctionsError/unexpectedStatusCode(_:_:)`` on a non-2xx response.
  @discardableResult
  public func invokeFunction(
    functionId: String,
    body: Data = Data(),
    contentType: String = "application/octet-stream",
    invokeType: FunctionInvokeType? = nil,
    intent: FunctionIntent? = nil,
    isDryRun: Bool? = nil,
    opcRequestId: String? = nil
  ) async throws -> Data {
    guard !functionId.trimmingCharacters(in: .whitespaces).isEmpty else {
      throw FunctionsError.missingRequiredParameter("functionId")
    }

    var req = try buildRequest(
      api: FunctionsAPI.invokeFunction(
        functionId: functionId,
        fnIntent: intent,
        fnInvokeType: invokeType,
        opcRequestId: opcRequestId,
        isDryRun: isDryRun
      ),
      endpoint: endpoint
    )
    // A function's output is opaque bytes, not JSON — accept anything. `buildRequest`
    // defaults both headers to `application/json`; override them here. `Content-Type`
    // must be set before signing because OCI signs it for requests that carry a body.
    req.setValue("*/*", forHTTPHeaderField: "accept")
    req.setValue(contentType, forHTTPHeaderField: "Content-Type")
    req.httpBody = body

    let (data, response) = try await httpClient.send(req, signer: signer, retry: retryConfig, logger: logger)
    guard let http = response as? HTTPURLResponse else {
      throw FunctionsError.invalidResponse("Invalid HTTP response")
    }
    guard (200..<300).contains(http.statusCode) else {
      let message = Self.errorMessage(from: data)
      logger.error("[Functions] invokeFunction HTTP \(http.statusCode): \(message)")
      throw FunctionsError.unexpectedStatusCode(http.statusCode, message)
    }
    return data
  }

  // MARK: - Private helpers

  /// Extracts a human-readable message from an OCI error body, falling back to raw text.
  private static func errorMessage(from data: Data) -> String {
    if let body = try? JSONDecoder().decode(DataBody.self, from: data) {
      return body.message
    }
    return String(data: data, encoding: .utf8) ?? ""
  }
}
