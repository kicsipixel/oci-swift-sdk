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

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

// API
public enum IAMAPI: API {
  /// Bulk delete resources
  case bulkDeleteResources(compartmentId: String, bulkDeleteResourcesDetails: BulkDeleteResourcesDetails, opcRequestId: String? = nil)
  /// Creates a compartment
  case createCompartment(compartmentDetails: CreateCompartmentDetails)
  /// Deletes a compartment
  case deleteCompartment(compartmentId: String)
  /// Gets a compartment
  case getCompartment(compartmentId: String)
  /// Lists compartments
  case listCompartments(
    compartmentId: String,
    page: String? = nil,
    limit: Int? = nil,
    accessLevel: AccessLevel? = nil,
    compartmentIdInSubtree: Bool? = nil,
    name: String? = nil,
    sortBy: SortBy? = nil,
    sortOrder: SortOrder? = nil,
    lifecycleState: String? = nil
  )
  /// Moves compartment
  case moveCompartment(compartmentId: String, moveCompartmentDetails: MoveCompartmentDetails, opcRequestId: String? = nil)
  /// Recovers compartment
  case recoverCompartment(compartmentId: String, opcRequestId: String? = nil)
  /// Updates compartment
  case updateCompartment(compartmentId: String, updateCompartmentDetails: UpdateCompartmentDetails)

  // Path
  public var path: String {
    switch self {
    case .bulkDeleteResources(let compartmentId, _, _):
      return "/20160918/compartments/\(compartmentId)/actions/bulkDeleteResources"
    case .createCompartment(_),
      .listCompartments(_, _, _, _, _, _, _, _, _):
      return "/20160918/compartments"
    case .deleteCompartment(let compartmentId),
      .getCompartment(let compartmentId),
      .updateCompartment(let compartmentId, _):
      return "/20160918/compartments/\(compartmentId)"
    case .moveCompartment(let compartmentId, _, _):
      return "/20160918/compartments/\(compartmentId)/actions/moveCompartment"
    case .recoverCompartment(let compartmentId, _):
      return "/20160918/compartments/\(compartmentId)/actions/recoverCompartment"
    }
  }

  // HTTPMethod
  public var method: HTTPMethod {
    switch self {
    case .getCompartment,
      .listCompartments:
      return .get
    case .bulkDeleteResources,
      .createCompartment,
      .moveCompartment,
      .recoverCompartment:
      return .post
    case .updateCompartment:
      return .put
    case .deleteCompartment:
      return .delete
    }
  }

  // QueryItems
  public var queryItems: [URLQueryItem]? {
    switch self {
    case .bulkDeleteResources,
      .createCompartment,
      .getCompartment,
      .deleteCompartment,
      .moveCompartment,
      .recoverCompartment,
      .updateCompartment:
      return nil
    case .listCompartments(let compartmentId, let page, let limit, let accesLevel, let compartmentIdInSubtree, let name, let sortBy, let sortOrder, let lifecycleState):
      let keyValuePairs: [(String, String?)] = [
        ("compartmentId", compartmentId),
        ("page", page),
        ("limit", limit.map(String.init)),
        ("accessLevel", accesLevel?.rawValue),
        ("compartmentIdInSubtree", compartmentIdInSubtree.map(String.init)),
        ("name", name),
        ("sortBy", sortBy?.rawValue),
        ("sortOrder", sortOrder?.rawValue),
        ("lifecycleState", lifecycleState),
      ]

      // Convert non-nil values into URLQueryItems
      let queryItems = keyValuePairs.compactMap { key, value in
        value.map { URLQueryItem(name: key, value: $0) }
      }

      return queryItems.isEmpty ? nil : queryItems
    }
  }

  // Headers
  public var headers: [String: String]? {
    switch self {
    case .bulkDeleteResources,
      .createCompartment,
      .deleteCompartment,
      .getCompartment,
      .listCompartments,
      .updateCompartment:
      return nil
    case .moveCompartment(_, _, let opcRequestId),
      .recoverCompartment(_, let opcRequestId):
      if let opcRequestId {
        return ["opc-client-request-id": opcRequestId]
      }
      return nil
    }
  }
}
