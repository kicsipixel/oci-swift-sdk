//
//  Signer.swift
//  
//
//  Created by Ilia Sazonov on 5/6/24.
//

import Foundation
import INIParser
import Crypto
import _CryptoExtras
import Logging

public let logger = Logger(label: "OCIKit")

// Linux compatibility
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// CryptoKit.Digest utils
extension Digest {
    var bytes: [UInt8] { Array(makeIterator()) }
    var data: Data { Data(bytes) }

    var hexStr: String {
        bytes.map { String(format: "%02X", $0) }.joined()
    }
    
    var base64: String {
        data.base64EncodedString()
    }
}

public protocol Signer {
    func sign(_ req: inout URLRequest) throws
}

public enum ConfigErrors: Error {
    case missingConfig, missingFingerprint, missingKeyfile, missingTenancy, missingUser, badKeyfile, notPemFormat
}

public struct APIKeySigner: Signer {
    struct Configuration {
        let name: String
        let privateKey: _RSA.Signing.PrivateKey
        let fingerprint: String
        let tenancyOCID: String
        let userOCID: String
        
        init(name: String, privateKey: _RSA.Signing.PrivateKey, fingerprint: String, tenancyOCID: String, userOCID: String) {
            self.name = name
            self.privateKey = privateKey
            self.fingerprint = fingerprint
            self.tenancyOCID = tenancyOCID
            self.userOCID = userOCID
        }
    }
    
    private let config: Configuration
    
    public func sign(_ req: inout URLRequest) throws {
        let verb = req.httpMethod?.lowercased() ?? ""
        let encodedPath = req.url?.relativePath.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        // add required headers
        req.addValue(req.url?.host() ?? "", forHTTPHeaderField: "host")
        // compose date header
        let currentDate = Date()
        let timezoneOffset =  TimeZone.current.secondsFromGMT()
        let epochDate = currentDate.timeIntervalSince1970
        let timezoneEpochOffset = (epochDate - Double(timezoneOffset))
        let timeZoneOffsetDate = Date(timeIntervalSince1970: timezoneEpochOffset)
        let formatter = DateFormatter()
        formatter.timeZone = .current
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss"
        let dateString: String = formatter.string(from: timeZoneOffsetDate) + " GMT"
        req.addValue(dateString, forHTTPHeaderField: "date")
        
        // start composing auth header and signing string
        var authHeader: [String] = [#"Signature version="1""#]
        var signingString: [String] = []

        var contentType = req.value(forHTTPHeaderField: "content-type") ?? ""
        if contentType.isEmpty {
            contentType = "application/json"
            req.addValue(contentType, forHTTPHeaderField: "content-type")
        }

        // extra headers for put, post
        if ["post","put"].contains(verb) {
            let contentLength: Int = req.httpBody?.count ?? 0
            let xContentSHA256: String = SHA256.hash(data: req.httpBody ?? "".data(using: .utf8)! ).base64
            // auth header and signing string must match in exact order
            authHeader.append(#"headers="date (request-target) host content-length content-type x-content-sha256""#)
            signingString.append("date: \(dateString)")
            signingString.append("(request-target): \(verb) \(encodedPath)")
            signingString.append("host: \(req.url?.host() ?? "")")
            signingString.append("content-length: \(contentLength)")
            signingString.append("content-type: \(contentType)")
            signingString.append("x-content-sha256: \(xContentSHA256)")
            // also, corresponding http headers must be present (order is not important)
            req.addValue(String(contentLength), forHTTPHeaderField: "content-length")
            req.addValue(xContentSHA256, forHTTPHeaderField: "x-content-sha256")
        } else {
            // auth header and signing string must match in exact order
            authHeader.append(#"headers="date (request-target) host""#)
            signingString.append("date: \(dateString)")
            signingString.append("(request-target): \(verb) \(encodedPath)")
            signingString.append("host: \(req.url?.host() ?? "")")
        }
        authHeader.append(#"keyId="\#(config.tenancyOCID)/\#(config.userOCID)/\#(config.fingerprint)""#)
        authHeader.append(#"algorithm="rsa-sha256""#)
        
        // signing
        logger.debug("signingString: \n\(signingString)\n----------------\n")
        let signature = try config.privateKey.signature(for: signingString.joined(separator: "\n").data(using: .ascii)!, padding: .insecurePKCS1v1_5)
        let signatureBase64String = signature.rawRepresentation.base64EncodedString()
        // appending signature to auth header
        authHeader.append(#"signature="\#(signatureBase64String)""#)
        // adding auth header to http headers
        req.addValue(authHeader.joined(separator: ","), forHTTPHeaderField: "Authorization")
    }
    
    public init(configFilePath: String, configName: String = "DEFAULT") throws {
        let configs = try INIParser(configFilePath)
        if configs.sections.keys.contains(configName) {
            guard let config = configs.sections[configName] else { throw ConfigErrors.missingConfig }
            guard let fingerprint = config["fingerprint"] else { throw ConfigErrors.missingFingerprint }
            guard let userOCID = config["user"] else { throw ConfigErrors.missingUser }
            guard let tenancyOCID = config["tenancy"] else { throw ConfigErrors.missingTenancy }
            guard let keyfilePath = config["key_file"] else { throw ConfigErrors.missingKeyfile }
            guard let keyFileContents = try? String(contentsOfFile: keyfilePath, encoding: .utf8) else { throw ConfigErrors.badKeyfile }
            guard let privateKey = try? _RSA.Signing.PrivateKey(pemRepresentation: keyFileContents) else { throw ConfigErrors.notPemFormat }
            self.config = Configuration(
                name: configName,
                privateKey: privateKey,
                fingerprint: fingerprint,
                tenancyOCID: tenancyOCID,
                userOCID: userOCID
            )
        } else {
            throw ConfigErrors.missingConfig
        }
    }
    
    init(_ config: Configuration) {
        self.config = config
    }
}


