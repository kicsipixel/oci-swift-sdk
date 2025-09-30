//
//  OCIKitTests.swift
//
//
//  Created by Ilia Sazonov on 5/8/24.
//

import Foundation
import XCTest
@testable import OCIKit

final class OCIKitTests: XCTestCase {
    let ociConfigFilePath = ProcessInfo.processInfo.environment["OCI_CONFIG_FILE"] ?? "\(NSHomeDirectory())/.oci/config"
    let ociProfileName = ProcessInfo.processInfo.environment["OCI_PROFILE"] ?? "DEFAULT"
    
    func test_if_config_file_exists() {
        let fileExists = FileManager.default.fileExists(atPath: ociConfigFilePath)
        XCTAssertTrue(fileExists, "OCI config file does not exist at path: \(ociConfigFilePath)")
    }
    
    func test_if_namespace_returns_valid_string() async throws {
        let signer = try APIKeySigner(configFilePath: ociConfigFilePath, configName: ociProfileName)
        let objectStorage =  try ObjectStorageClient(region: .fra, signer: signer)
        let namespace = try await objectStorage.getNamespace(compartmentId: "ocid1.tenancy.oc1..aaaaaaaapt3esrvwldrfekea5ucasigr2nof7tjx6ysyb4oo3yiqgx2d72ha")
        
        XCTAssertFalse(namespace.isEmpty, "Namespace should not be empty")
    }
    
    func test_if_config_file_is_valid() async throws {
        let signer = try APIKeySigner(configFilePath: ociConfigFilePath, configName: ociProfileName)
        guard let userRegion = try extractUserRegion(from: ociConfigFilePath) else {
            XCTFail("Could not extract user region from config file")
            return
        }
        
        var req = URLRequest(url: URL(string: "https://objectstorage.\(userRegion).oraclecloud.com/n")!)
        try signer.sign(&req)
        print(">>> All Headers: >>> \n\(req.allHTTPHeaderFields ?? [:])\n>>>>>>>>\n")
        
        let (data, response) = try await URLSession.shared.data(for: req)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            XCTFail("Invalid HTTP response")
            return
        }
        
        XCTAssertEqual(httpResponse.statusCode, 200, "Expected HTTP 200 OK, got \(httpResponse.statusCode)")
        
        let responseBody = String(data: data, encoding: .utf8)
        print("Response: \(responseBody ?? "<no body>")")
    }
    
    func testHealthNER() async throws {
        guard let endpoint = ProcessInfo.processInfo.environment["HEALTH_NER_ENDPOINT"], !endpoint.isEmpty else {
            print("testHealthNER not configured")
            return
        }
        print("ociProfileName: \(ociProfileName)")
        let signer = try APIKeySigner(configFilePath: ociConfigFilePath, configName: ociProfileName)
        let healthNER = BatchDetectHealthEntity(region: .iad, signer: signer)
        let req = BatchDetectHealthEntity.BatchDetectHealthEntityDetails(
            documents: [TextDocument(
                key: UUID().uuidString,
                languageCode: "en",
                text: "lung cancer"
            )],
            endpointId: endpoint
        )
        let response = try await healthNER.getHealthEntities(req)
        print("reponse: \(response)")
    }
    
    func testGenAICohere() async throws {
        guard
            let compartment = ProcessInfo.processInfo.environment["GENAI_COMPARTMENT_OCID"], !compartment.isEmpty,
            let modelId = ProcessInfo.processInfo.environment["GENAI_COHERE_MODEL_OCID"], !modelId.isEmpty
        else {
            print("testGenAICohere not configured")
            return
        }
        let signer = try APIKeySigner(configFilePath: ociConfigFilePath, configName: ociProfileName)
        let getText = GenerateText(region: .ord, signer: signer)
        let req = GenerateText.GenerateTextDetails(
            compartmentId: compartment,
            inferenceRequest: GenerateText.CohereLlmInferenceRequest(
                frequencyPenalty: nil,
                isEcho: false,
                isStream: false,
                maxTokens: nil,
                numGenerations: nil,
                presencePenalty: nil,
                prompt: "tell me about LLMs",
                returnLikelihoods: nil,
                stopSequences: nil,
                temperature: nil,
                topK: nil,
                topP: nil,
                truncate: nil
            ),
            servingMode: GenerateText.OnDemandServingMode(modelId: modelId)
        )
        let response = try await getText.getCompletion(req)
        print("reponse: \(response)")
    }
    
    func testGenAILlama() async throws {
        guard
            let compartment = ProcessInfo.processInfo.environment["GENAI_COMPARTMENT_OCID"], !compartment.isEmpty,
            let modelId = ProcessInfo.processInfo.environment["GENAI_LLAMA_MODEL_OCID"], !modelId.isEmpty
        else {
            print("testGenAILlama not configured")
            return
        }
        let signer = try APIKeySigner(configFilePath: ociConfigFilePath, configName: ociProfileName)
        let getText = GenerateText(region: .ord, signer: signer)
        let req = GenerateText.GenerateTextDetails(
            compartmentId: compartment,
            inferenceRequest: GenerateText.LlamaLlmInferenceRequest(
                frequencyPenalty: nil,
                isEcho: false,
                isStream: false,
                logProbs: nil, maxTokens: nil,
                numGenerations: nil,
                presencePenalty: nil,
                prompt: "tell me about LLMs",
                stop: nil,
                temperature: nil,
                topK: nil,
                topP: nil
            ),
            servingMode: GenerateText.OnDemandServingMode(modelId: modelId)
        )
        let response = try await getText.getCompletion(req)
        print("reponse: \(response)")
    }
}
