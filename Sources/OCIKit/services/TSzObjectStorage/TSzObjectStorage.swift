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
import Logging

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

public struct TSzObjectStorageClient {
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

  // MARK: - Creates bucket
  /// Creates a bucket in the given namespace with a bucket name and optional user-defined metadata. Avoid entering confidential information in bucket names.
  /// The request body must contain a single [CreateBucketDetails](https://docs.oracle.com/en-us/iaas/api/#/en/objectstorage/20160918/datatypes/CreateBucketDetails) resource.
  ///
  /// - Parameters:
  ///     - namespaceName: The Object Storage namespace used for the request.
  ///     - opcClientRequestId: Optional client request ID for tracing.
  ///  - Returns: The response body will contain a single Bucket resource.
  public func createBucket(namespaceName: String, bucket: CreateBucketDetails, opcClientRequestId: String? = nil) async throws -> Bucket? {
    guard let endpoint else {
      throw ObjectStorageError.missingRequiredParameter("No endpoint has been set")
    }

    let api = ObjectStorageAPI.createBucket(namespaceName: namespaceName, opcClientRequestId: opcClientRequestId)
    var req = try buildRequest(objectStorageAPI: api, endpoint: endpoint)

    do {
      let payload: Data
      do {
        payload = try JSONEncoder().encode(bucket)
      }
      catch {
        throw ObjectStorageError.jsonEncodingError("CreateBucketDetails cannot be encoded to data")
      }

      req.httpBody = payload

      try signer.sign(&req)

      let (data, response) = try await URLSession.shared.data(for: req)

      guard let httpResponse = response as? HTTPURLResponse else {
        throw ObjectStorageError.invalidResponse("Invalid HTTP response")
      }

      if httpResponse.statusCode != 200 {
        throw ObjectStorageError.invalidResponse("Unexpected status code: \(httpResponse.statusCode)")
      }

      do {
        let bucket = try JSONDecoder().decode(Bucket.self, from: data)
        return bucket
      }
      catch {
        throw ObjectStorageError.jsonDecodingError("Failed to decode response data to Bucket")
      }
    }
    catch {
      throw error
    }
  }

  // MARK: - Deletes bucket
  /// Deletes a bucket if the bucket is already empty.
  /// If the bucket is not empty, use `deleteObject` first.
  /// You cannot delete a bucket that has a multipart upload in progress or a pre-authenticated request associated with it.
  ///
  /// - Parameters:
  ///   - namespaceName: The Object Storage namespace used for the request.
  ///   - bucketName: The name of the bucket. Avoid entering confidential information. Example: `"my-new-bucket1"`
  ///   - opcClientRequestId: Optional client request ID for tracing.
  ///
  /// - Returns: A `Response` object with data of type `Void`.
  ///
  /// TODO:
  /// - retryConfig: The retry configuration to apply to this operation. If no value is provided,
  /// the service-level retry configuration will be used. If `nil` is explicitly provided,
  /// the operation will not retry.
  ///  - ifMatch: The entity tag (ETag) to match with the ETag of an existing resource.
  ///  If the specified ETag matches, GET and HEAD requests will return the resource,
  ///  and PUT and POST requests will upload the resource.
  public func deleteBucket(namespaceName: String, bucketName: String, opcClientRequestId: String? = nil) async throws {
    guard let endpoint else {
      throw ObjectStorageError.missingRequiredParameter("No endpoint has been set")
    }

    let api = ObjectStorageAPI.deleteBucket(namespaceName: namespaceName, bucketName: bucketName, opcClientRequestId: opcClientRequestId)
    var req = try buildRequest(objectStorageAPI: api, endpoint: endpoint)

    try signer.sign(&req)

    let (_, response) = try await URLSession.shared.data(for: req)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw ObjectStorageError.invalidResponse("Invalid HTTP response")
    }

    if httpResponse.statusCode != 204 {
      throw ObjectStorageError.invalidResponse("Unexpected status code: \(httpResponse.statusCode)")
    }

    let headers = convertHeadersToDictionary(httpResponse)
    if let opcRequestId = headers["opc-request-id"] {
      logger.debug("The \(bucketName) bucket was delete from \(namespaceName) namespace. RequestID: \(opcRequestId)")
    }
  }
  // MARK: - Gets bucket
  /// Gets the current representation of the given bucket in the given Object Storage namespace.
  /// - Parameters:
  ///     - namespaceName: The Object Storage namespace used for the request.
  ///     - bucketName: The name of the bucket. Avoid entering confidential information.
  ///     - opcClientRequestId: Optional client request ID for tracing.
  /// - Returns: A bucket representation for the requested bucket.
  ///
  /// TODO:
  ///     - retryConfig: Optional The retry configuration to apply to this operation. If no key is provided,
  ///     then the service-level retry configuration defined by `retryConfig` will be used.
  ///     If an explicit `nil` value is provided, the operation will not retry.
  ///   - ifMatch: Optional The entity tag (ETag) to match with the ETag of an existing resource.
  ///     If the specified ETag matches the ETag of the existing resource, `GET` and `HEAD` requests
  ///     will return the resource, and `PUT` and `POST` requests will upload the resource.
  ///   - ifNoneMatch: Optional The entity tag (ETag) to avoid matching. Wildcards ('*') are not allowed.
  ///     If the specified ETag does not match the ETag of the existing resource, the request returns
  ///     the expected response. If the ETag matches, the request returns an HTTP 304 status without a response body.
  ///   - opcClientRequestId: Optional The client request ID for tracing.
  ///   - fields: Optional A list of fields to include in the bucket summary. Possible values are:
  ///     - `approximateCount`: Approximate number of objects in the bucket.
  ///     - `approximateSize`: Total approximate size in bytes of all objects in the bucket.
  ///     - `autoTiering`: State of auto tiering on the bucket.
  ///
  public func getBucket(namespaceName: String, bucketName: String, opcClientRequestId: String? = nil) async throws -> Bucket? {
    guard let endpoint else {
      throw ObjectStorageError.missingRequiredParameter("No endpoint has been set")
    }

    let api = ObjectStorageAPI.getBucket(namespaceName: namespaceName, bucketName: bucketName, opcClientRequestId: opcClientRequestId)
    var req = try buildRequest(objectStorageAPI: api, endpoint: endpoint)

    try signer.sign(&req)

    let (data, response) = try await URLSession.shared.data(for: req)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw ObjectStorageError.invalidResponse("Invalid HTTP response")
    }

    if httpResponse.statusCode != 200 {
      throw ObjectStorageError.invalidResponse("Unexpected status code: \(httpResponse.statusCode)")
    }

    do {
      let bucket = try JSONDecoder().decode(Bucket.self, from: data)
      return bucket
    }
    catch {
      throw ObjectStorageError.jsonDecodingError("Failed to decode response data to Bucket")
    }
  }

  // MARK: - Gets namespace
  /// Each Oracle Cloud Infrastructure tenant is assigned one unique and uneditable Object Storage namespace. The namespace
  /// is a system-generated string assigned during account creation. For some older tenancies, the namespace string may be
  /// the tenancy name in all lower-case letters. You cannot edit a namespace.
  ///
  /// GetNamespace returns the name of the Object Storage namespace for the user making the request.
  /// If an optional compartmentId query parameter is provided, GetNamespace returns the namespace name of the corresponding
  /// tenancy, provided the user has access to it.
  ///
  /// - Parameters:
  ///   - compartmentId: his is an optional field representing either the tenancy [OCID](https://docs.cloud.oracle.com/Content/General/Concepts/identifiers.htm) or the compartment [OCID](https://docs.cloud.oracle.com/Content/General/Concepts/identifiers.htm) within the tenancy whose Object Storage namespace is to be retrieved.
  ///   - opcClientRequestId: Optional client request ID for tracing.
  ///   - retryConfig: Optional retry configuration to apply to this operation. If `nil`, the default service-level retry configuration is used. If explicitly set to `nil`, the operation will not retry.
  ///
  /// - Returns: A `String` containing the Object Storage namespace.
  public func getNamespace(compartmentId: String? = nil) async throws -> String {
    guard let endpoint else {
      throw ObjectStorageError.missingRequiredParameter("No endpoint has been set")
    }

    let api = ObjectStorageAPI.getNamespace()
    var req = try buildRequest(objectStorageAPI: api, endpoint: endpoint)

    try signer.sign(&req)

    let (data, response) = try await URLSession.shared.data(for: req)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw ObjectStorageError.invalidResponse("Invalid HTTP response")
    }

    if httpResponse.statusCode != 200 {
      throw ObjectStorageError.invalidResponse("Unexpected status code: \(httpResponse.statusCode)")
    }

    guard let responseBody = String(data: data, encoding: .utf8) else {
      throw ObjectStorageError.invalidUTF8
    }

    return responseBody
  }

  // MARK: - Gets namespace metadata
  /// Retrieves metadata for the Object Storage namespace, including `defaultS3CompartmentId` and `defaultSwiftCompartmentId`.
  ///
  /// Any user with the `OBJECTSTORAGE_NAMESPACE_READ` permission can view the current metadata.
  /// If you are not authorized, contact an administrator. Administrators can refer to
  /// [Getting Started with Policies](https://docs.cloud.oracle.com/Content/Identity/Concepts/policygetstarted.htm)
  /// for guidance on granting access.
  ///
  /// - Parameters:
  ///   - namespaceName: The Object Storage namespace used for the request.
  ///   - opcClientRequestId: The client request ID for tracing.
  ///
  /// - Returns: A `Response` object containing `NamespaceMetadata`.
  ///
  /// TODO:
  ///   - retryConfig: The retry configuration to apply to this operation. If no value is provided, the service-level retry configuration will be used. If `nil` is explicitly provided, the operation will not retry.
  public func getNamespaceMetadata(namespaceName: String, opcClientRequestId: String? = nil) async throws -> NamespaceMetadata? {
    guard let endpoint else {
      throw ObjectStorageError.missingRequiredParameter("No endpoint has been set")
    }

    let api = ObjectStorageAPI.getNamespaceMetadata(namespaceName: namespaceName, opcClientRequestId: opcClientRequestId)
    var req = try buildRequest(objectStorageAPI: api, endpoint: endpoint)

    try signer.sign(&req)

    let (data, response) = try await URLSession.shared.data(for: req)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw ObjectStorageError.invalidResponse("Invalid HTTP response")
    }

    if httpResponse.statusCode != 200 {
      throw ObjectStorageError.invalidResponse("Unexpected status code: \(httpResponse.statusCode)")
    }

    let namespaceMetadata = try JSONDecoder().decode(NamespaceMetadata.self, from: data)

    return namespaceMetadata
  }
  // MARK: - Heads bucket
  /// Efficiently checks whether a bucket exists and retrieves the current entity tag (ETag) for the bucket.
  ///
  /// - Parameters:
  ///   - namespaceName: The Object Storage namespace used for the request.
  ///   - bucketName: The name of the bucket. Avoid entering confidential information. Example: `"my-new-bucket1"`
  ///   - opcClientRequestId: Optional client request ID for tracing.
  ///
  /// - Returns: A `Response` object with no data payload (`Void`).
  ///
  /// TODO:
  ///  - retryConfig: The retry configuration to apply to this operation. If no value is provided,
  ///  the service-level retry configuration will be used. If `nil` is explicitly provided, the operation will not retry.
  ///  - ifMatch: The entity tag (ETag) to match with the ETag of an existing resource.
  ///  If the specified ETag matches, GET and HEAD requests will return the resource,
  ///  and PUT and POST requests will upload the resource.
  ///  - ifNoneMatch: The entity tag (ETag) to avoid matching. Wildcards (`*`) are not allowed.
  ///  If the specified ETag does not match the existing resource, the request returns the expected response.
  ///  If it matches, the request returns HTTP 304 without a response body.
  public func headBucket(namespaceName: String, bucketName: String, opcClientRequestId: String? = nil) async throws {
    guard let endpoint else {
      throw ObjectStorageError.missingRequiredParameter("No endpoint has been set")
    }

    let api = ObjectStorageAPI.headBucket(namespaceName: namespaceName, bucketName: bucketName, opcClientRequestId: opcClientRequestId)
    var req = try buildRequest(objectStorageAPI: api, endpoint: endpoint)

    try signer.sign(&req)

    let (_, response) = try await URLSession.shared.data(for: req)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw ObjectStorageError.invalidResponse("Invalid HTTP response")
    }

    if httpResponse.statusCode != 200 {
      throw ObjectStorageError.invalidResponse("Unexpected status code: \(httpResponse.statusCode)")
    }

    let headers = convertHeadersToDictionary(httpResponse)
    if let etag = headers["Etag"], let opcRequestId = headers["opc-request-id"] {
      logger.debug("ETag: \(etag), opc-request-id: \(opcRequestId)")
    }
  }

  // MARK: - Lists buckets
  /// Gets a list of all BucketSummary items in a compartment. A BucketSummary contains only summary fields for the bucket
  /// and does not contain fields like the user-defined metadata.
  ///
  /// ListBuckets returns a BucketSummary containing at most 1000 buckets. To paginate through more buckets, use the returned
  /// `opc-next-page` value with the `page` request parameter.
  ///
  /// To use this and other API operations, you must be authorized in an IAM policy. If you are not authorized,
  /// talk to an administrator. If you are an administrator who needs to write policies to give users access, see
  /// [Getting Started with Policies](https://docs.cloud.oracle.com/Content/Identity/Concepts/policygetstarted.htm).
  ///
  /// - Parameters:
  ///     - namespaceName: The Object Storage namespace used for the request.
  ///     - compartmentId: The ID of the compartment in which to list buckets.
  ///     - opcClientRequestId: Optional client request ID for tracing.
  ///  - Returns: The response body will contain an array of BucketSummary resources.
  ///
  ///  TODO:
  ///  - limit: Int / query (1-1000)
  ///  - page: String / query (1-1024)
  ///  - fields: Array / query (tags only allowed)
  public func listBuckets(namespaceName: String, compartmentId: String, opcClientRequestId: String? = nil) async throws -> [BucketSummary] {
    guard let endpoint else {
      throw ObjectStorageError.missingRequiredParameter("No endpoint has been set")
    }

    let api = ObjectStorageAPI.listBuckets(namespaceName: namespaceName, compartmentId: compartmentId, opcClientRequestId: opcClientRequestId)
    var req = try buildRequest(objectStorageAPI: api, endpoint: endpoint)

    try signer.sign(&req)

    let (data, response) = try await URLSession.shared.data(for: req)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw ObjectStorageError.invalidResponse("Invalid HTTP response")
    }

    if httpResponse.statusCode != 200 {
      throw ObjectStorageError.invalidResponse("Unexpected status code: \(httpResponse.statusCode)")
    }

    let bucketSummary = try JSONDecoder().decode([BucketSummary].self, from: data)

    return bucketSummary
  }

  // MARK: - Reencrypts bucket
  /// Re-encrypts the unique data encryption key used for each object in the bucket using the most recent
  /// version of the master encryption key assigned to the bucket.
  ///
  /// All data encryption keys are encrypted by a master encryption key. By default, Oracle manages these keys,
  /// but you can assign a custom key through the Oracle Cloud Infrastructure Key Management service.
  /// The `kmsKeyId` property of the bucket determines which master encryption key is assigned.
  /// If you assign a new master encryption key, you can call this API to re-encrypt all data encryption keys
  /// with the newly assigned key. You may also want to re-encrypt if the assigned key has been rotated
  /// since objects were last added. If no `kmsKeyId` is associated with the bucket, the call will fail.
  ///
  /// This API initiates a work request to re-encrypt the data encryption keys of all objects created
  /// before the time of the call. The operation may take a long time depending on the number and size of objects.
  /// All versions of objects will be re-encrypted, regardless of whether versioning is enabled or suspended.
  ///
  /// - Parameters:
  ///   - namespaceName: The Object Storage namespace used for the request.
  ///   - bucketName: The name of the bucket. Avoid entering confidential information. Example: `"my-new-bucket1"`
  ///   - opcClientRequestId: Optional client request ID for tracing.
  ///
  /// - Returns: A `Response` object with no data payload (`Void`).
  ///
  /// TODO:
  ///- retryConfig: The retry configuration to apply to this operation. If no value is provided, the service-level retry configuration will be used. If `nil` is explicitly provided, the operation will not retry.
  public func reencryptBucket(namespaceName: String, bucketName: String, opcClientRequestId: String? = nil) async throws {
    guard let endpoint else {
      throw ObjectStorageError.missingRequiredParameter("No endpoint has been set")
    }

    let api = ObjectStorageAPI.reencryptBucket(namespaceName: namespaceName, bucketName: bucketName, opcClientRequestId: opcClientRequestId)
    var req = try buildRequest(objectStorageAPI: api, endpoint: endpoint)

    try signer.sign(&req)

    let (_, response) = try await URLSession.shared.data(for: req)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw ObjectStorageError.invalidResponse("Invalid HTTP response")
    }

    if httpResponse.statusCode != 202 {
      throw ObjectStorageError.invalidResponse("Unexpected status code: \(httpResponse.statusCode)")
    }

    let headers = convertHeadersToDictionary(httpResponse)
    if let opcRequestId = headers["opc-request-id"], let opcWorkRequestId = headers["opc-work-request-id"] {
      logger.debug("opc-request-id: \(opcRequestId), opc-work-request-id: \(opcWorkRequestId)")
    }
  }

  // MARK: - Updates bucket
  /// Performs a partial or full update of a bucket's user-defined metadata.
  ///
  /// Use `updateBucket` to move a bucket from one compartment to another within the same tenancy.
  /// Provide the `compartmentId` of the target compartment. For more details, see:
  /// [Moving Resources to a Different Compartment](https://docs.cloud.oracle.com/iaas/Content/Identity/Tasks/managingcompartments.htm#moveRes).
  ///
  /// - Parameters:
  ///   - namespaceName: The Object Storage namespace used for the request.
  ///   - bucketName: The name of the bucket. Avoid entering confidential information. Example: `"my-new-bucket1"`
  ///   - updateBucketDetails: The request object containing metadata updates for the bucket.
  ///   - opcClientRequestId: Optional client request ID for tracing.
  ///
  /// - Returns: A `Response` object containing the updated `Bucket`.
  ///
  /// TODO:
  ///  - ifMatch: The entity tag (ETag) to match with the ETag of an existing resource. If the specified ETag matches, GET and HEAD requests will return the resource, and PUT and POST requests will upload the resource.
  ///  - retryConfig: The retry configuration to apply to this operation. If no value is provided, the service-level retry configuration will be used. If `nil` is explicitly provided, the operation will not retry.
  public func updateBucket(
    namespaceName: String,
    bucketName: String,
    bucket: UpdateBucketDetails,
    opcClientRequestId: String? = nil
  ) async throws -> Bucket? {
    guard let endpoint else {
      throw ObjectStorageError.missingRequiredParameter("No endpoint has been set")
    }

    let api = ObjectStorageAPI.updateBucket(namespaceName: namespaceName, bucketName: bucketName, opcClientRequestId: opcClientRequestId)
    var req = try buildRequest(objectStorageAPI: api, endpoint: endpoint)

    do {
      let payload: Data
      do {
        payload = try JSONEncoder().encode(bucket)
      }
      catch {
        throw ObjectStorageError.jsonEncodingError("CreateBucketDetails cannot be encoded to data")
      }

      req.httpBody = payload

      try signer.sign(&req)

      let (data, response) = try await URLSession.shared.data(for: req)

      guard let httpResponse = response as? HTTPURLResponse else {
        throw ObjectStorageError.invalidResponse("Invalid HTTP response")
      }

      if httpResponse.statusCode != 200 {
        throw ObjectStorageError.invalidResponse("Unexpected status code: \(httpResponse.statusCode)")
      }

      do {
        let bucket = try JSONDecoder().decode(Bucket.self, from: data)
        return bucket
      }
      catch {
        throw ObjectStorageError.jsonDecodingError("Failed to decode response data to Bucket")
      }
    }
    catch {
      throw error
    }
  }
}

// Retry configuration
public struct RetryConfig {
  let maxAttempts: Int
  let baseDelay: TimeInterval
}

// Error types
public enum ObjectStorageError: Error {
  case missingRequiredParameter(String)
  case invalidURL(String)
  case invalidResponse(String)
  case invalidUTF8
  case jsonEncodingError(String)
  case jsonDecodingError(String)
}

// Convert HTTPURLResponse to dictionary
func convertHeadersToDictionary(_ httpResponse: HTTPURLResponse) -> [String: String] {
  return httpResponse.allHeaderFields
    .compactMapValues { "\($0)" }
    .reduce(into: [String: String]()) { dict, pair in
      if let key = pair.key as? String {
        dict[key] = pair.value
      }
    }
}
