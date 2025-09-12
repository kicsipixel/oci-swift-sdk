import Foundation

public struct ObjectStorageClient {
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
        } else {
            guard let region = region else {
                throw ObjectStorageError.missingRequiredParameter("Either endpoint or region must be specified.")
            }
            self.region = region
            let host = Service.objectstorage.getHost(in: region)
            self.endpoint = URL(string: "https://\(host)")
        }
    }
    
    public func makeRequest(path: String) throws -> URLRequest {
        guard let endpoint else {
            throw ObjectStorageError.missingRequiredParameter("No endpoint available")
        }
        var req = URLRequest(url: endpoint.appendingPathComponent(path))
        try signer.sign(&req)
        return req
    }

    
    // MARK: - List buckets
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
    /// Parameters:
    ///     - namespaceName: The Object Storage namespace used for the request.
    ///     - compartmentId: The ID of the compartment in which to list buckets
    public func listBuckets(namespaceName: String, compartmentId: String) throws { }
}

// Retry configuration
public struct RetryConfig {
    let maxAttempts: Int
    let baseDelay: TimeInterval
}

// Error types
public enum ObjectStorageError: Error {
    case missingRequiredParameter(String)
}
