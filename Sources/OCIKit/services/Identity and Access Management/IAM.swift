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
  let logger: Logger

  // MARK: - Initialization
  /// Initialize the object storage client
  /// Parameters:
  ///     - region: A region used to determine the service endpoint.
  ///     - endpoint: The fully qualified endpoint URL
  ///     - signer: A signer implementation which can be used by this client.
  public init(region: Region? = nil, endpoint: String? = nil, signer: Signer, retryConfig: RetryConfig? = nil, logger: Logger = Logger(label: "IAMClient")) throws {
    self.signer = signer
    self.retryConfig = retryConfig
    self.logger = logger

    if let endpoint, let endpointURL = URL(string: endpoint) {
      self.endpoint = endpointURL
      self.region = nil
    }
    else {
      guard let region = region else {
        throw ObjectStorageError.missingRequiredParameter("Either endpoint or region must be specified.")
      }
      self.region = region
      let host = Service.iam.getHost(in: region)
      self.endpoint = URL(string: "https://\(host)/n")
    }
  }

  // MARK: - Creates a compartment
  /// Creates a new compartment inside the specified parent compartment.
  ///
  /// Specify the parent compartment’s OCID as the `compartmentId` in the request body.
  /// The tenancy itself is simply the root compartment.
  /// For more information about OCIDs, see
  /// [Resource Identifiers](https://docs.cloud.oracle.com/Content/General/Concepts/identifiers.htm).
  ///
  /// You must provide a **name** for the new compartment.
  /// The name must be unique across all compartments within the same parent.
  /// This name (or the OCID) can later be used when writing IAM policies that apply
  /// to the compartment. For more details, see
  /// [How Policies Work](https://docs.cloud.oracle.com/Content/Identity/policieshow/how-policies-work.htm).
  ///
  /// You must also provide a **description** for the compartment.
  /// The description does not need to be unique and can be changed at any time using
  /// `updateCompartment`.
  ///
  /// After the request is submitted, the new compartment’s `lifecycleState` will
  /// temporarily be `.CREATING`.
  /// Before using the compartment, ensure that its state has transitioned to `.ACTIVE`.
  ///
  /// - Parameters:
  ///   - details: The request payload describing the new compartment to create.
  ///
  /// - Returns: A response containing the newly created `Compartment`.
  public func createCompartment(
    compartmentDetails: CreateCompartmentDetails
  ) async throws -> Compartment {
    guard let endpoint else {
      throw IAMError.missingRequiredParameter("No endpoint has been set")
    }
    let api = IAMAPI.createCompartment(compartmentDetails: compartmentDetails)
    var req = try buildRequest(api: api, endpoint: endpoint)

    let payload: Data
    do {
      payload = try JSONEncoder().encode(compartmentDetails)
    }
    catch {
      throw IAMError.jsonEncodingError("CompartmentDetails cannot be encoded to data")
    }

    req.httpBody = payload
    try signer.sign(&req)

    let (data, response) = try await URLSession.shared.data(for: req)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw IAMError.invalidResponse("Invalid HTTP response")
    }

    if httpResponse.statusCode != 200 {
      let errorBody = try JSONDecoder().decode(DataBody.self, from: data)
      self.logger.error("[createCompartment] \(errorBody.code) (\(httpResponse.statusCode)): \(errorBody.message)")
      throw IAMError.unexpectedStatusCode(httpResponse.statusCode, errorBody.message)
    }

    let createdCompartment = try JSONDecoder().decode(Compartment.self, from: data)
    return createdCompartment
  }

  // MARK: - Deletes a compartment
  /// Deletes the specified compartment.
  ///
  /// The compartment **must be empty** before it can be deleted.
  ///
  /// - Parameters:
  ///   - compartmentId:
  ///     The OCID of the compartment to delete.
  ///
  /// - Returns:
  ///   A response object with no associated data.
  public func deleteCompartment(
    compartmentId: String
  ) async throws {
    guard let endpoint else {
      throw IAMError.missingRequiredParameter("No endpoint has been set")
    }
    let api = IAMAPI.deleteCompartment(compartmentId: compartmentId)
    var req = try buildRequest(api: api, endpoint: endpoint)

    try signer.sign(&req)

    let (data, response) = try await URLSession.shared.data(for: req)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw IAMError.invalidResponse("Invalid HTTP response")
    }

    if httpResponse.statusCode != 202 {
      let errorBody = try JSONDecoder().decode(DataBody.self, from: data)
      self.logger.error("[deleteCompartment] \(errorBody.code) (\(httpResponse.statusCode)): \(errorBody.message)")
      throw ObjectStorageError.unexpectedStatusCode(httpResponse.statusCode, errorBody.message)
    }

    let headers = convertHeadersToDictionary(httpResponse)
    if let opcClientRequestId = headers["opc-client-request-id"], let opcRequestId = headers["opc-request-id"] {
      logger.debug("opc-client-request-id: \(opcClientRequestId), opc-request-id: \(opcRequestId)")
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
  public func listCompartments(
    compartmentId: String,
    page: String? = nil,
    limit: Int? = nil,
    accessLevel: AccessLevel? = nil,
    compartmentIdInSubtree: Bool? = nil,
    name: String? = nil,
    sortBy: SortBy? = nil,
    sortOrder: SortOrder? = nil,
    lifecycleState: String? = nil
  ) async throws -> [Compartment] {
    guard let endpoint else {
      throw IAMError.missingRequiredParameter("No endpoint has been set")
    }
    let api = IAMAPI.listCompartments(
      compartmentId: compartmentId,
      page: page,
      limit: limit,
      accessLevel: accessLevel,
      compartmentIdInSubtree: compartmentIdInSubtree,
      name: name,
      sortBy: sortBy,
      sortOrder: sortOrder,
      lifecycleState: lifecycleState
    )
    var req = try buildRequest(api: api, endpoint: endpoint)

    try signer.sign(&req)
    let (data, response) = try await URLSession.shared.data(for: req)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw IAMError.invalidResponse("Invalid HTTP response")
    }

    if httpResponse.statusCode != 200 {
      let errorBody = try JSONDecoder().decode(DataBody.self, from: data)
      self.logger.error("[listCompartments] \(errorBody.code) (\(httpResponse.statusCode)): \(errorBody.message)")
      throw ObjectStorageError.unexpectedStatusCode(httpResponse.statusCode, errorBody.message)
    }

    do {
      let listOfCompartments = try JSONDecoder().decode([Compartment].self, from: data)
      return listOfCompartments
    }
    catch {
      throw IAMError.jsonDecodingError("Failed to decode response data to Compartments")
    }
  }
}
