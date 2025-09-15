//
//  ObjectStorageClient.swift
//  oci-swift-sdk
//
//  Created by Ilia Sazonov on 9/13/25.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct ObjectStorageClient {
    private let host: String
    private let signer: Signer
    private let session: URLSession

    public init(region: Region, signer: Signer) {
        self.host = Service.objectstorage.getHost(in: region)
        self.signer = signer
        self.session = URLSession.shared
    }

    public enum APIError: Error {
        case badURL
    }

    // GET /n
    // Returns the Object Storage namespace for the tenancy. Optionally accepts compartmentId query.
    public func getNamespace(compartmentId: String? = nil, opcClientRequestId: String? = nil) async throws -> String {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/n"
        if let compartmentId {
            components.queryItems = [
                URLQueryItem(name: "compartmentId", value: compartmentId)
            ]
        }

        guard let url = components.url else { throw APIError.badURL }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "accept")
        if let opcClientRequestId {
            req.setValue(opcClientRequestId, forHTTPHeaderField: "opc-client-request-id")
        }

        try signer.sign(&req)
        logger.debug("http request: \(req)")
        let headers = req.allHTTPHeaderFields?.values.joined(separator: "\n") ?? ""
        logger.debug("http headers: \(headers)")

        let (data, _) = try await session.data(for: req)
        let debugString = String(data: data, encoding: .utf8) ?? ""
        logger.debug("http response: \(debugString)")

        // The API returns a bare JSON string like "namespaceValue"
        let namespace = try JSONDecoder().decode(String.self, from: data)
        return namespace
    }
}
