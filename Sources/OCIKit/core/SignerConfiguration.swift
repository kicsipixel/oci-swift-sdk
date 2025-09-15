//
//  SignerConfiguration.swift
//
//  Shared configuration loader and validator for all signers.
//
//  Created by Alex (AI) on 9/12/25.
//

import Foundation
import INIParser
import Crypto
import _CryptoExtras

public enum ConfigErrors: Error {
    case missingConfig
    case missingFingerprint
    case missingKeyfile
    case missingTenancy
    case missingUser
    case missingSecurityTokenFile
    case badKeyfile
    case notPemFormat
    case badSecurityTokenFile
}

private func expandTilde(_ path: String) -> String {
    (path as NSString).expandingTildeInPath
}

private func extractPemPrivateKeyBlock(from raw: String) -> String? {
    let variants: [(begin: String, end: String)] = [
        ("-----BEGIN PRIVATE KEY-----", "-----END PRIVATE KEY-----"),
        ("-----BEGIN RSA PRIVATE KEY-----", "-----END RSA PRIVATE KEY-----")
    ]

    for v in variants {
        if let beginRange = raw.range(of: v.begin),
           let endRange = raw.range(of: v.end),
           beginRange.lowerBound < endRange.upperBound {
            let block = raw[beginRange.lowerBound...endRange.upperBound]
            return String(block)
        }
    }

    // Fallback with regex to be robust if needed
    if let regex = try? NSRegularExpression(pattern: "-----BEGIN (?:RSA )?PRIVATE KEY-----[\\s\\S]*?-----END (?:RSA )?PRIVATE KEY-----", options: []),
       let match = regex.firstMatch(in: raw, options: [], range: NSRange(location: 0, length: (raw as NSString).length)) {
        let nsRaw = raw as NSString
        return nsRaw.substring(with: match.range)
    }

    return nil
}

public struct SignerConfiguration {
    public let name: String
    public let privateKey: _RSA.Signing.PrivateKey
    public let tenancyOCID: String?
    public let userOCID: String?
    public let fingerprint: String?
    public let securityToken: String?

    public init(
        name: String,
        privateKey: _RSA.Signing.PrivateKey,
        tenancyOCID: String?,
        userOCID: String?,
        fingerprint: String?,
        securityToken: String?
    ) {
        self.name = name
        self.privateKey = privateKey
        self.tenancyOCID = tenancyOCID
        self.userOCID = userOCID
        self.fingerprint = fingerprint
        self.securityToken = securityToken
    }

    public static func fromFileForAPIKey(configFilePath: String, configName: String = "DEFAULT") throws -> SignerConfiguration {
        let configs = try INIParser(configFilePath)
        guard configs.sections.keys.contains(configName), let section = configs.sections[configName] else {
            throw ConfigErrors.missingConfig
        }
        print("Loading config for \(configName) from \(configFilePath)...\n")
        guard let fingerprint = section["fingerprint"] else { throw ConfigErrors.missingFingerprint }
        guard let userOCID = section["user"] else { throw ConfigErrors.missingUser }
        guard let tenancyOCID = section["tenancy"] else { throw ConfigErrors.missingTenancy }
        guard let keyfilePath = section["key_file"] else { throw ConfigErrors.missingKeyfile }
        guard let keyFileContents = try? String(contentsOfFile: expandTilde(keyfilePath), encoding: .utf8) else { throw ConfigErrors.badKeyfile }

        let pemString = extractPemPrivateKeyBlock(from: keyFileContents) ?? keyFileContents
        guard let privateKey = try? _RSA.Signing.PrivateKey(pemRepresentation: pemString) else { throw ConfigErrors.notPemFormat }

        return SignerConfiguration(
            name: configName,
            privateKey: privateKey,
            tenancyOCID: tenancyOCID,
            userOCID: userOCID,
            fingerprint: fingerprint,
            securityToken: nil
        )
    }

    public static func fromFileForSecurityToken(configFilePath: String, configName: String = "DEFAULT") throws -> SignerConfiguration {
        let configs = try INIParser(configFilePath)
        guard configs.sections.keys.contains(configName), let section = configs.sections[configName] else {
            throw ConfigErrors.missingConfig
        }

        guard let keyfilePath = section["key_file"] else { throw ConfigErrors.missingKeyfile }
        guard let keyFileContents = try? String(contentsOfFile: expandTilde(keyfilePath), encoding: .utf8) else { throw ConfigErrors.badKeyfile }

        let pemString = extractPemPrivateKeyBlock(from: keyFileContents) ?? keyFileContents
        guard let privateKey = try? _RSA.Signing.PrivateKey(pemRepresentation: pemString) else { throw ConfigErrors.notPemFormat }

        guard let tokenFilePath = section["security_token_file"] else { throw ConfigErrors.missingSecurityTokenFile }
        guard let token = try? String(contentsOfFile: expandTilde(tokenFilePath), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty else {
            throw ConfigErrors.badSecurityTokenFile
        }

        return SignerConfiguration(
            name: configName,
            privateKey: privateKey,
            tenancyOCID: section["tenancy"],
            userOCID: section["user"],
            fingerprint: section["fingerprint"],
            securityToken: token
        )
    }
}
