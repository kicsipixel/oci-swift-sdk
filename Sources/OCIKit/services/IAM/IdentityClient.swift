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

public struct IdentityClient {
    let config: Config?
    let region: Region?
    let endpoint: URL?
    let signer: Signer
    let proxySettings: ProxySettings?
    let retryConfig: RetryConfig?
    
    // MARK: - Initialization
    /// Creates a new `IdentityClient`.
    ///
    /// Notes:
    /// - If `config` is not specified, the global `OCI.config` will be used.
    ///
    /// - Either a `region` or an `endpoint` must be specified. If an `endpoint` is provided, it will take precedence over the `region`.
    ///   A region may be specified either in the `config` or via the `region` parameter. If both are provided, the `region` parameter will be used.
    ///
    /// - Parameters:
    ///   - config: A `Config` object. If not provided, a default global config will be used.
    ///   - region: A region string used to determine the service endpoint. Typically corresponds to a value in `OCI.Regions.REGION_ENUM`, but may be any valid string.
    ///   - endpoint: A fully qualified endpoint URL. If specified, it overrides the region.
    ///   - signer: A signer implementation (`OCI.BaseSigner`) used by this client. If not provided, a signer will be constructed from the config.
    ///     This is useful for instance principals authentication, where an instance principals signer can be passed directly.
    ///   - proxySettings: Optional proxy configuration (`OCI.ApiClientProxySettings`) for environments requiring HTTP proxy usage.
    ///   - retryConfig: Optional retry configuration (`OCI.Retry.RetryConfig`) applied across all operations. Can be overridden per operation.
    ///     If `nil`, operations will not perform retries.
    ///
    /// Additional Notes:
    /// - If the signer is an `InstancePrincipalsSecurityTokenSigner` or `SecurityTokenSigner` and no config is provided (as these are self-sufficient),
    ///   a dummy config will be created for the `ApiClient` constructor.
    /// - If no signer is provided (or it's not an instance principals signer) and no config is supplied, the config will be loaded from the default file.
    public init(config: Config? = nil, region: Region? = nil, endpoint: String? = nil, signer: Signer, proxySettings: ProxySettings? = nil, retryConfig: RetryConfig? = nil) throws {
        self.config = config
        self.signer = signer
        self.proxySettings = proxySettings
        self.retryConfig = retryConfig
        
        if let endpoint, let endpointURL = URL(string: endpoint) {
            self.endpoint = endpointURL
            self.region = nil
        } else {
            guard let region = region else {
                throw IdentityClientError.missingRequiredParameter("Either endpoint or region must be specified.")
            }
            self.region = region
            let host = Service.iam.getHost(in: region)
            self.endpoint = URL(string: "https://\(host)")
        }
    }
    
    // MARK: - Lists compartments
    /// Lists the compartments within a specified compartment.
    ///
    /// The returned list depends on the values of several parameters:
    /// - For all compartments except the tenancy (root compartment), this operation returns only the first-level child compartments of the specified `compartmentId`.
    ///   Subcompartments (grandchildren) are not included.
    /// - The `accessLevel` parameter determines whether to return only compartments for which the requester has INSPECT permissions on at least one resource,
    ///   either directly or indirectly (e.g., via a subcompartment).
    /// - The `compartmentIdInSubtree` parameter applies only when listing compartments in the tenancy (root compartment). When set to `true`, the entire hierarchy
    ///   of compartments may be returned. To retrieve all compartments and subcompartments in the tenancy, set `compartmentIdInSubtree` to `true` and `accessLevel` to `ANY`.
    ///
    /// See [Where to Get the Tenancy's OCID and User's OCID](https://docs.cloud.oracle.com/Content/API/Concepts/apisigningkey.htm#five).
    ///
    /// - Parameters:
    ///   - compartmentId: The OCID of the compartment. The tenancy is simply the root compartment.
    ///   - retryConfig: Optional retry configuration (`OCI.Retry.RetryConfig`) for this operation. If not provided, the service-level retry configuration will be used.
    ///     If explicitly set to `nil`, the operation will not retry.
    ///   - page: The value of the `opc-next-page` response header from the previous "List" call.
    ///   - limit: The maximum number of items to return in a paginated "List" call.
    ///   - accessLevel: Determines which compartments to return. Valid values are `ANY` and `ACCESSIBLE`. Default is `ANY`.
    ///     - `ACCESSIBLE`: Returns only compartments where the user has INSPECT permissions directly or indirectly.
    ///     - `ANY`: Permissions are not checked.
    ///   - compartmentIdInSubtree: Default is `false`. Can only be set to `true` when listing compartments in the tenancy.
    ///     When `true`, the hierarchy is traversed and all compartments and subcompartments are returned based on `accessLevel`.
    ///   - name: A filter to return only resources that exactly match the given name.
    ///   - sortBy: The field to sort by. Valid values are `TIMECREATED` (default descending) and `NAME` (default ascending, case-sensitive).
    ///     Note: Some "List" operations allow filtering by Availability Domain. If not specified, resources are grouped and sorted by domain.
    ///   - sortOrder: The sort order to use: `ASC` or `DESC`. The `NAME` sort order is case-sensitive.
    ///   - lifecycleState: A filter to return only resources matching the given lifecycle state (case-insensitive).
    ///
    /// - Returns: A response object containing an array of `OCI.Identity.Models.Compartment`.
    ///
    /// - Note: See [example usage](https://docs.cloud.oracle.com/en-us/iaas/tools/ruby-sdk-examples/latest/identity/list_compartments.rb.html).
    
    public func listCompartments(compartmentId: String) async throws -> String {
        guard let endpoint else {
            throw IdentityClientError.missingRequiredParameter("No endpoint has been set")
        }
        
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw IdentityClientError.invalidURL("")
        }
        components.path = "/20160918/compartments"
        
        components.queryItems = [
            URLQueryItem(name: "compartmentId", value: compartmentId)
        ]
        
        guard let url = components.url else {
            throw IdentityClientError.invalidURL("URL components could not be converted to a valid URL")
        }

        var req = URLRequest(url: url)
        
        try signer.sign(&req)
        
        let (data, response) = try await URLSession.shared.data(for: req)
        
        guard let responseBody = String(data: data, encoding: .utf8) else {
            throw IdentityClientError.invalidUTF8
        }
        
        return responseBody
    }
}

// Retry configuration
public struct RetryConfig {
    let maxAttempts: Int
    let baseDelay: TimeInterval
}

// Config object
public struct Config {}

// Proxy settings
public struct ProxySettings {}

// Error types
public enum IdentityClientError: Error {
    case missingRequiredParameter(String)
    case invalidURL(String)
    case invalidResponse(String)
    case invalidUTF8
}
