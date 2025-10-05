//===----------------------------------------------------------------------===//
//
// This source file is part of the oci-swift-sdk open source project
//
// Copyright (c) 2025 Szabolcs Tóth and the oci-swift-sdk project authors
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

public struct IAMClient {
  let endpoint: URL?
  let region: Region?
  let retryConfig: RetryConfig?
  let signer: Signer

  // MARK: - Initialization
  /// Initialize the object storage client
  /// Parameters:
  ///     - region: A region used to determine the service endpoint.
  ///     - endpoint: The fully qualified endpoint URL
  ///     - signer: A signer implementation which can be used by this client.
  ///
  ///  TODO:
  ///     - proxySettings: If your environment requires you to use a proxy server for outgoing HTTP requests the details for the proxy can be provided in this parameter
  ///     - retryConfig: The retry configuration for this service client
  ///
  ///     Either a region or an endpoint must be specified. If an endpoint is specified, it will be used instead of the region.
  public init(region: Region? = nil, endpoint: String? = nil, signer: Signer, retryConfig: RetryConfig? = nil) throws {
    self.signer = signer
    self.retryConfig = retryConfig

    if let endpoint, let endpointURL = URL(string: endpoint) {
      self.endpoint = endpointURL
      self.region = nil
    }
    else {
      guard let region = region else {
        throw ObjectStorageError.missingRequiredParameter("Either endpoint or region must be specified.")
      }
      self.region = region
      let host = Service.objectstorage.getHost(in: region)
      self.endpoint = URL(string: "https://\(host)/n")
    }
  }

  // MARK: - Lists compartments
  /// Lists the compartments within a specified compartment.
  /// The returned list depends on the values of several parameters.
  ///
  /// - Note:
  ///   - For all compartments except the tenancy (root compartment), this operation returns only the first-level child compartments.
  ///   - Subcompartments of those children (i.e., grandchildren) are not included.
  ///
  /// - Parameters:
  ///   - compartmentId: The OCID of the compartment. The tenancy is simply the root compartment.
  ///   - accessLevel: Determines whether to return only compartments for which the requestor has `INSPECT` permissions on at least one resource,
  ///     either directly or indirectly (e.g., in a subcompartment). Valid values are `ANY` and `ACCESSIBLE`. Default is `ANY`.
  ///   - compartmentIdInSubtree: Applies only when listing compartments on the tenancy. When `true`, the entire hierarchy of compartments is returned.
  ///     To list all compartments and subcompartments in the tenancy, set `compartmentIdInSubtree` to `true` and `accessLevel` to `ANY`.
  ///   - page: The value of the `opc-next-page` response header from a previous list call, used for pagination.
  ///   - limit: The maximum number of items to return in a paginated list call.
  ///   - name: A filter to return only compartments that match the given name exactly.
  ///   - sortBy: The field to sort by. Valid values are `TIMECREATED` (default descending) and `NAME` (default ascending, case-sensitive).
  ///   - sortOrder: The sort order to use: `ASC` or `DESC`. The `NAME` sort order is case-sensitive.
  ///   - lifecycleState: A filter to return only compartments matching the given lifecycle state. Case-insensitive.

  ///
  /// - Returns: An array of `Compartment` objects representing the compartments in the specified compartment.
  ///
  /// TODO:
  ///   - retryConfig: Optional retry configuration for this operation. If not provided, the service-level retry config is used. If explicitly set to `nil`, no retries are performed.
  public func listCompartments(
    compartmentId: String,
    accessLevel: AccessLevel? = nil,
    compartmentIdInSubtree: Bool? = nil,
    page: String? = nil,
    limit: Int? = nil,
    name: String? = nil,
    sortBy: SortBy? = nil,
    sortOrder: SortOrder? = nil,
    lifecycleState: String? = nil
  ) async throws -> [Compartment] {}
}
