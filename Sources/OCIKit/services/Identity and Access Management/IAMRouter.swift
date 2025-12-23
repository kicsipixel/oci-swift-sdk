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
  /// Creates a compartment
  case createCompartment(compartmentDetails: CreateCompartmentDetails)
  /// Deletes a compartment
  case deleteCompartment(compartmentId: String)
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

  // Path
  public var path: String {
    switch self {
    case .createCompartment(_),
      .listCompartments(_, _, _, _, _, _, _, _, _):
      return "/20160918/compartments"
    case .deleteCompartment(let compartmentId):
      return "/20160918/compartments/\(compartmentId)"
    }
  }

  // HTTPMethod
  public var method: HTTPMethod {
    switch self {
    case .listCompartments:
      return .get
    case .createCompartment:
      return .post
    case .deleteCompartment:
      return .delete
    }
  }

  // QueryItems
  public var queryItems: [URLQueryItem]? {
    switch self {
    case .createCompartment,
      .deleteCompartment:
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
    case .createCompartment,
      .deleteCompartment,
      .listCompartments:
      return nil
    }
  }
}
