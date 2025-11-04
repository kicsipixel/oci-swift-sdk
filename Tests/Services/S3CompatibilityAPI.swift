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
import OCIKit
import Testing

struct S3CompatibilityTest {
    
    let accessKeyId: String = "6OrdAHO8Z47besRN1VOIpVorGgHdMta+XFhwM1fn6A4="
    let secretAccessKey: String = "4d2d2013112ba074d2c0fcd9a8478033632bd9b0"
    
    @Test func listObjectsInBucketWithCustomerSecretKey() async throws {
        let accessKeyId = "6OrdAHO8Z47besRN1VOIpVorGgHdMta+XFhwM1fn6A4="
        let secretAccessKey = "4d2d2013112ba074d2c0fcd9a8478033632bd9b0"

        let namespaceName = "frjfldcyl3la"
        let region: Region = .fra
        let bucketName = "test_bucket_by_sdk"

        let endpoint = "https://\(namespaceName).compat.objectstorage.\(region.urlPart).oci.customer-oci.com"
        let url = URL(string: "\(endpoint)/\(bucketName)")!

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/xml", forHTTPHeaderField: "Accept")

        let credentials = AWSCredentials(accessKey: accessKeyId, secretKey: secretAccessKey)
        let signer = SigV4Signer(credentials: credentials, region: region, service: "s3")
        try signer.signRequest(&request)

        let (data, response) = try await URLSession.shared.data(for: request)
        let body = String(data: data, encoding: .utf8) ?? ""

        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        print("Status: \(http.statusCode)\n\(body)")

        #expect(http.statusCode == 200)
    }
}
