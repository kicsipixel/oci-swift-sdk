//
//  InstancePrincipalTest.swift
//  oci-swift-sdk
//
//  Created by Alex (AI) on 9/13/25.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import OCIKit

struct InstancePrincipalObjectStorageTest {
    private func fetchIMDSRegion(timeoutSeconds: TimeInterval = 5) -> String? {
        let base = ProcessInfo.processInfo.environment["OCI_METADATA_BASE_URL"] ?? "http://169.254.169.254/opc/v2"
        guard let url = URL(string: "\(base)/instance/region") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer Oracle", forHTTPHeaderField: "Authorization")

        let sem = DispatchSemaphore(value: 0)
        var result: String?
        URLSession.shared.dataTask(with: req) { data, resp, err in
            defer { sem.signal() }
            guard err == nil,
                  let data = data,
                  let http = resp as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode)
            else { return }
            result = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
        }.resume()
        _ = sem.wait(timeout: .now() + timeoutSeconds)
        return result
    }

    @Test func getNamespace_withInstancePrincipalSigner() async throws {
        guard let regionRaw = fetchIMDSRegion() else {
            print("Skipping Instance Principal test: IMDS region unavailable (not running on OCI instance?)")
            return
        }

        guard let region = Region.from(regionId: regionRaw) else {
            print("Skipping Instance Principal test: IMDS returned unsupported or short region '\(regionRaw)'; Region enum expects long-form (e.g. us-phoenix-1).")
            return
        }

        let signer = try InstancePrincipalSigner()
        let client = try ObjectStorageClient(region: region, signer: signer)

        let namespace = try await client.getNamespace()
        print("Namespace (Instance Principal): \(namespace)")
        #expect(!namespace.isEmpty)
    }
}
