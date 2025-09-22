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
  /// Copies object
  case copyObject(namespaceName: String, bucketName: String, opcClientRequestId: String? = nil)
  /// Creates bucket
  case createBucket(namespaceName: String, opcClientRequestId: String? = nil)
  /// Deletes bucket
  case deleteBucket(namespaceName: String, bucketName: String, opcClientRequestId: String? = nil)
  /// Deletes object
  case deleteObject(namespaceName: String, bucketName: String, objectName: String, opcClientRequestId: String? = nil, versionId: String? = nil)
  /// Gets bucket
  case getBucket(namespaceName: String, bucketName: String, opcClientRequestId: String? = nil)
  /// Gets object
  case getObject(
    namespaceName: String,
    bucketName: String,
    objectName: String,
    versionId: String? = nil,
    opcClientRequestId: String? = nil,
    range: String? = nil,
    opcSseCustomerAlgorithm: String? = nil,
    opcSseCustomerKey: String? = nil,
    opcSseCustomerKeySha256: String? = nil,
    httpResponseContentDisposition: String? = nil,
    httpResponseCacheControl: String? = nil,
    httpResponseContentType: String? = nil,
    httpResponseContentLanguage: String? = nil,
    httpResponseContentEncoding: String? = nil,
    httpResponseExpires: String? = nil
  )
  /// HEAD bucket
  case headBucket(namespaceName: String, bucketName: String, opcClientRequestId: String? = nil)
  /// HEAD object
  case headObject(
    namespaceName: String,
    bucketName: String,
    objectName: String,
    versionId: String? = nil,
    opcClientRequestId: String? = nil,
    opcSseCustomerAlgorithm: String? = nil,
    opcSseCustomerKey: String? = nil,
    opcSseCustomerKeySha256: String? = nil
  )
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
  /// Updates namespace metadata
  case updateNamespaceMetadata(namespaceName: String, opcClientRequestId: String? = nil)

  // Path
  public var path: String {
    switch self {
    case .getNamespace:
      return "/n"
    case .getNamespaceMetadata(let namespaceName, _),
      .updateNamespaceMetadata(let namespaceName, _):
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
    case .copyObject(let namespaceName, let bucketName, _):
      return "/n/\(namespaceName)/b/\(bucketName)/actions/copyObject"
    case .deleteObject(let namespaceName, let bucketName, let objectName, _, _),
      .getObject(let namespaceName, let bucketName, let objectName, _, _, _, _, _, _, _, _, _, _, _, _),
      .headObject(let namespaceName, let bucketName, let objectName, _, _, _, _, _):
      return "/n/\(namespaceName)/b/\(bucketName)/o/\(objectName)"
    }
  }

  // HTTPMethod
  public var method: HTTPMethod {
    switch self {
    case .copyObject,
      .createBucket,
      .reencryptBucket,
      .updateBucket:
      return .post
    case .deleteBucket,
      .deleteObject:
      return .delete
    case .getNamespace,
      .getBucket,
      .getObject,
      .getNamespaceMetadata,
      .listBuckets:
      return .get
    case .headBucket,
      .headObject:
      return .head
    case .updateNamespaceMetadata:
      return .put
    }
  }

  // QueryItems
  public var queryItems: [URLQueryItem]? {
    switch self {
    case .copyObject,
      .createBucket,
      .deleteBucket,
      .getBucket,
      .getNamespaceMetadata,
      .headBucket,
      .reencryptBucket,
      .updateBucket,
      .updateNamespaceMetadata:
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

    case .deleteObject(_, _, _, _, let versionId):
      if let versionId {
        return [
          URLQueryItem(name: "versionId", value: versionId)
        ]
      }
      return nil

    case .getObject(
      _,
      _,
      _,
      let versionId,
      _,
      _,
      _,
      _,
      _,
      let httpResponseContentDisposition,
      let httpResponseCacheControl,
      let httpResponseContentType,
      let httpResponseContentLanguage,
      let httpResponseContentEncoding,
      let httpResponseExpires
    ):
      let keyValuePairs: [(String, String?)] = [
        ("versionId", versionId),
        ("contentDisposition", httpResponseContentDisposition),
        ("cacheControl", httpResponseCacheControl),
        ("contentType", httpResponseContentType),
        ("contentLanguage", httpResponseContentLanguage),
        ("contentEncoding", httpResponseContentEncoding),
        ("expires", httpResponseExpires),
      ]

      // Convert non-nil values into URLQueryItems
      let queryItems = keyValuePairs.compactMap { key, value in
        value.map { URLQueryItem(name: key, value: $0) }
      }

      return queryItems.isEmpty ? nil : queryItems

    case .headObject(_, _, _, let versionId, _, _, _, _):
      if let versionId {
        return [
          URLQueryItem(name: "versionId", value: versionId)
        ]
      }
      return nil
    }
  }

  // Headers
  public var headers: [String: String]? {
    switch self {
    case .copyObject(_, _, let opcClientRequestId),
      .createBucket(_, let opcClientRequestId),
      .deleteBucket(_, _, let opcClientRequestId),
      .deleteObject(_, _, _, let opcClientRequestId, _),
      .getBucket(_, _, let opcClientRequestId),
      .getObject(_, _, _, _, let opcClientRequestId, _, _, _, _, _, _, _, _, _, _),
      .getNamespace(_, let opcClientRequestId),
      .getNamespaceMetadata(_, let opcClientRequestId),
      .headBucket(_, _, let opcClientRequestId),
      .headObject(_, _, _, _, let opcClientRequestId, _, _, _),
      .listBuckets(_, _, let opcClientRequestId),
      .reencryptBucket(_, _, let opcClientRequestId),
      .updateBucket(_, _, let opcClientRequestId),
      .updateNamespaceMetadata(_, let opcClientRequestId):
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
