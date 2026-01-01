//===----------------------------------------------------------------------===//
//
// This source file is part of the oci-swift-sdk open source project
//
// Copyright (c) 2025 Ilia Sazonov and the oci-swift-sdk project authors
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

/// API routes for the OCI Secrets Retrieval service.
///
/// Use the Secret Retrieval API to retrieve secrets and secret versions from vaults.
/// For more information, see [Managing Secrets](https://docs.oracle.com/en-us/iaas/Content/KeyManagement/Tasks/managingsecrets.htm).
public enum SecretsAPI: API {
  /// Gets a secret bundle that matches either the specified `stage`, `secretVersionName`,
  /// or `versionNumber` parameter.
  ///
  /// If none of these parameters are provided, the bundle for the secret version
  /// marked as `CURRENT` will be returned.
  case getSecretBundle(
    secretId: String,
    versionNumber: Int? = nil,
    secretVersionName: String? = nil,
    stage: SecretStage? = nil,
    opcRequestId: String? = nil
  )

  /// Gets a secret bundle by secret name and vault ID, and secret version that matches
  /// either the specified `stage`, `secretVersionName`, or `versionNumber` parameter.
  ///
  /// If none of these parameters are provided, the bundle for the secret version
  /// marked as `CURRENT` is returned.
  ///
  /// - Note: This endpoint uses POST method despite being a read operation.
  case getSecretBundleByName(
    secretName: String,
    vaultId: String,
    versionNumber: Int? = nil,
    secretVersionName: String? = nil,
    stage: SecretStage? = nil,
    opcRequestId: String? = nil
  )

  /// Lists all secret bundle versions for the specified secret.
  case listSecretBundleVersions(
    secretId: String,
    limit: Int? = nil,
    page: String? = nil,
    sortBy: SecretVersionSortBy? = nil,
    sortOrder: SortOrder? = nil,
    opcRequestId: String? = nil
  )

  // MARK: - Path

  public var path: String {
    switch self {
    case .getSecretBundle(let secretId, _, _, _, _):
      return "/20190301/secretbundles/\(secretId)"
    case .getSecretBundleByName:
      return "/20190301/secretbundles/actions/getByName"
    case .listSecretBundleVersions(let secretId, _, _, _, _, _):
      return "/20190301/secretbundles/\(secretId)/versions"
    }
  }

  // MARK: - HTTP Method

  public var method: HTTPMethod {
    switch self {
    case .getSecretBundle,
      .listSecretBundleVersions:
      return .get
    case .getSecretBundleByName:
      // Note: POST method despite being a read operation
      return .post
    }
  }

  // MARK: - Query Items

  public var queryItems: [URLQueryItem]? {
    switch self {
    case .getSecretBundle(_, let versionNumber, let secretVersionName, let stage, _):
      let keyValuePairs: [(String, String?)] = [
        ("versionNumber", versionNumber.map(String.init)),
        ("secretVersionName", secretVersionName),
        ("stage", stage?.rawValue),
      ]

      let queryItems = keyValuePairs.compactMap { key, value in
        value.map { URLQueryItem(name: key, value: $0) }
      }

      return queryItems.isEmpty ? nil : queryItems

    case .getSecretBundleByName(
      let secretName,
      let vaultId,
      let versionNumber,
      let secretVersionName,
      let stage,
      _
    ):
      let keyValuePairs: [(String, String?)] = [
        ("secretName", secretName),
        ("vaultId", vaultId),
        ("versionNumber", versionNumber.map(String.init)),
        ("secretVersionName", secretVersionName),
        ("stage", stage?.rawValue),
      ]

      let queryItems = keyValuePairs.compactMap { key, value in
        value.map { URLQueryItem(name: key, value: $0) }
      }

      return queryItems.isEmpty ? nil : queryItems

    case .listSecretBundleVersions(_, let limit, let page, let sortBy, let sortOrder, _):
      let keyValuePairs: [(String, String?)] = [
        ("limit", limit.map(String.init)),
        ("page", page),
        ("sortBy", sortBy?.rawValue),
        ("sortOrder", sortOrder?.rawValue),
      ]

      let queryItems = keyValuePairs.compactMap { key, value in
        value.map { URLQueryItem(name: key, value: $0) }
      }

      return queryItems.isEmpty ? nil : queryItems
    }
  }

  // MARK: - Headers

  public var headers: [String: String]? {
    switch self {
    case .getSecretBundle(_, _, _, _, let opcRequestId),
      .getSecretBundleByName(_, _, _, _, _, let opcRequestId),
      .listSecretBundleVersions(_, _, _, _, _, let opcRequestId):
      if let opcRequestId {
        return ["opc-request-id": opcRequestId]
      }
      return nil
    }
  }
}
