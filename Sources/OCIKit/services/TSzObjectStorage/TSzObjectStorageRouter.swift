//===----------------------------------------------------------------------===//
//
// This source file is part of the oci-swift-sdk open source project
//
// Copyright (c) 2025 Szabolcs Toth and the oci-swift-sdk project authors
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

// HTTP methods
public enum HTTPMethod: String {
  case get = "GET"
  case post = "POST"
  case put = "PUT"
  case delete = "DELETE"
  case head = "HEAD"
}

// Protocol description
public protocol API {
  var path: String { get }
  var method: HTTPMethod { get }
  var queryItems: [URLQueryItem]? { get }
  var headers: [String: String]? { get }
}

// API
public enum ObjectStorageAPI: API {
  /// Creates bucket
  case createBucket(namespaceName: String, opcClientRequestId: String? = nil)
  /// Deletes bucket
  case deleteBucket(namespaceName: String, bucketName: String, opcClientRequestId: String? = nil)
  /// Gets bucket
  case getBucket(namespaceName: String, bucketName: String, opcClientRequestId: String? = nil)
  /// HEAD bucket
  case headBucket(namespaceName: String, bucketName: String, opcClientRequestId: String? = nil)
  /// Gets namespace
  case getNamespace(compartmentId: String? = nil, opcClientRequestId: String? = nil)
  /// Gets namespace metadata
  case getNamespaceMetadata(namespaceName: String, opcClientRequestId: String? = nil)
  /// Lists buckets
  case listBuckets(namespaceName: String, compartmentId: String, opcClientRequestId: String? = nil)
  /// Reencrypts bucket
  case reencryptBucket(namespaceName: String, bucketName: String, opcClientRequestId: String? = nil)
  /// Updates bucket
  case updateBucket(namespaceName: String, bucketName: String, opcClientRequestId: String? = nil)

  // Path
  public var path: String {
    switch self {
    case .getNamespace:
      return "/n"
    case .getNamespaceMetadata(let namespaceName, _):
      return "/n/\(namespaceName)"
    case .createBucket(let namespaceName, _),
      .listBuckets(let namespaceName, _, _):
      return "/n/\(namespaceName)/b"
    case .deleteBucket(let namespaceName, let bucketName, _),
      .getBucket(let namespaceName, let bucketName, _),
      .headBucket(let namespaceName, let bucketName, _),
      .updateBucket(let namespaceName, let bucketName, _):
      return "/n/\(namespaceName)/b/\(bucketName)"
    case .reencryptBucket(let namespaceName, let bucketName, _):
      return "/n/\(namespaceName)/b/\(bucketName)/actions/reencrypt"
    }
  }

  // HTTPMethod
  public var method: HTTPMethod {
    switch self {
    case .createBucket,
      .reencryptBucket,
      .updateBucket:
      return .post
    case .deleteBucket:
      return .delete
    case .getNamespace,
      .getBucket,
      .getNamespaceMetadata,
      .listBuckets:
      return .get
    case .headBucket:
      return .head
    }
  }

  // QueryItems
  public var queryItems: [URLQueryItem]? {
    switch self {
    case .createBucket,
      .deleteBucket,
      .getBucket,
      .getNamespaceMetadata,
      .headBucket,
      .reencryptBucket,
      .updateBucket:
      return nil
    case .getNamespace(let compartmentId, _):
      if let compartmentId {
        return [
          URLQueryItem(name: "compartmentId", value: compartmentId)
        ]
      }
      return nil
    case .listBuckets(_, let compartmentId, _):
      return [URLQueryItem(name: "compartmentId", value: compartmentId)]
    }
  }

  // Headers
  public var headers: [String: String]? {
    switch self {
    case .createBucket(_, let opcClientRequestId),
      .deleteBucket(_, _, let opcClientRequestId),
      .getBucket(_, _, let opcClientRequestId),
      .getNamespace(_, let opcClientRequestId),
      .getNamespaceMetadata(_, let opcClientRequestId),
      .headBucket(_, _, let opcClientRequestId),
      .listBuckets(_, _, let opcClientRequestId),
      .reencryptBucket(_, _, let opcClientRequestId),
      .updateBucket(_, _, let opcClientRequestId):
      if let opcClientRequestId {
        return ["opc-client-request-id": opcClientRequestId]
      }
      return nil
    }
  }
}

/// Build request from components defined in ObjectStorageAPIRouter
public func buildRequest(objectStorageAPI: API, endpoint: URL) throws -> URLRequest {
  guard
    var components = URLComponents(
      url: endpoint,
      resolvingAgainstBaseURL: false
    )
  else {
    throw ObjectStorageError.invalidURL("Enpoint URL is invalid")
  }

  // Build path
  components.path = objectStorageAPI.path

  // Add query items
  components.queryItems = objectStorageAPI.queryItems
  guard let url = components.url else {
    throw ObjectStorageError.invalidURL("Could not construct final URL")
  }

  // Build request
  var request = URLRequest(url: url)
  request.httpMethod = objectStorageAPI.method.rawValue

  // Add headers
  objectStorageAPI.headers?.forEach { key, value in
    request.addValue(value, forHTTPHeaderField: key)
  }
  request.setValue("application/json", forHTTPHeaderField: "accept")
  request.setValue("application/json", forHTTPHeaderField: "Content-Type")

  return request
}
