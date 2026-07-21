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

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// API routes for the OCI Functions **invoke** endpoint (API version `20181201`).
///
/// This router only covers `InvokeFunction`. Application/function lifecycle
/// management (create/list/update/delete) is intentionally out of scope — do it
/// with Terraform, the OCI Console, or another SDK. See the
/// [Functions API](https://docs.oracle.com/en-us/iaas/api/#/en/functions/20181201/Function/InvokeFunction).
///
/// > Important: An invocation is sent to a function's **own** invoke endpoint
/// > (the `invokeEndpoint` field of the `Function` resource), not to a regional
/// > service endpoint. ``FunctionsInvokeClient`` is therefore constructed with an
/// > explicit invoke endpoint URL.
public enum FunctionsAPI: API {
  /// The service API version path segment shared by every route.
  static let version = "/20181201"

  /// Invokes a function by OCID.
  ///
  /// - Parameters:
  ///   - functionId: The OCID of the function to invoke.
  ///   - fnIntent: Optional `fn-intent` header hint (`httprequest` / `cloudevent`).
  ///   - fnInvokeType: Optional `fn-invoke-type` header (`sync` / `detached`).
  ///   - opcRequestId: Optional client-supplied request id for tracing.
  ///   - isDryRun: When `true`, the platform validates the request without executing the function.
  case invokeFunction(
    functionId: String,
    fnIntent: FunctionIntent? = nil,
    fnInvokeType: FunctionInvokeType? = nil,
    opcRequestId: String? = nil,
    isDryRun: Bool? = nil
  )

  // MARK: - Path

  public var path: String {
    switch self {
    case .invokeFunction(let functionId, _, _, _, _):
      return "\(Self.version)/functions/\(functionId)/actions/invoke"
    }
  }

  // MARK: - HTTP Method

  public var method: HTTPMethod {
    switch self {
    case .invokeFunction:
      return .post
    }
  }

  // MARK: - Query Items

  public var queryItems: [URLQueryItem]? { nil }

  // MARK: - Headers

  public var headers: [String: String]? {
    switch self {
    case .invokeFunction(_, let fnIntent, let fnInvokeType, let opcRequestId, let isDryRun):
      var headers: [String: String] = [:]
      if let fnIntent { headers["fn-intent"] = fnIntent.rawValue }
      if let fnInvokeType { headers["fn-invoke-type"] = fnInvokeType.rawValue }
      if let opcRequestId { headers["opc-request-id"] = opcRequestId }
      if let isDryRun { headers["is-dry-run"] = isDryRun ? "true" : "false" }
      return headers.isEmpty ? nil : headers
    }
  }
}
