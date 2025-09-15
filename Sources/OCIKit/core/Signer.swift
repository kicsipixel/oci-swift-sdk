//
//  Signer.swift
//  
//
//  Created by Ilia Sazonov on 5/6/24.
//

import Foundation
import Crypto
import _CryptoExtras
import Logging

public var logger = Logger(label: "OCIKit")

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

public protocol X509FederationClientProtocol {
    func currentSecurityToken() throws -> String
    func currentPrivateKey() throws -> _RSA.Signing.PrivateKey
}

enum RequestSigner {
    static func sign(
        _ req: inout URLRequest,
        with privateKey: _RSA.Signing.PrivateKey,
        keyId: String,
        includeBodyForVerbs: Set<String> = ["post", "put", "patch"]
    ) throws {
        let verb = req.httpMethod?.lowercased() ?? ""
        let encodedPath = req.url?.relativePath.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        req.addValue(req.url?.host ?? "", forHTTPHeaderField: "host")
        let currentDate = Date()
        let timezoneOffset = TimeZone.current.secondsFromGMT()
        let epochDate = currentDate.timeIntervalSince1970
        let timezoneEpochOffset = (epochDate - Double(timezoneOffset))
        let timeZoneOffsetDate = Date(timeIntervalSince1970: timezoneEpochOffset)
        let formatter = DateFormatter()
        formatter.timeZone = .current
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss"
        let dateString: String = formatter.string(from: timeZoneOffsetDate) + " GMT"
        req.addValue(dateString, forHTTPHeaderField: "date")

        var authHeader: [String] = [#"Signature version="1""#]
        var signingString: [String] = []

        var contentType = req.value(forHTTPHeaderField: "content-type") ?? ""
        if contentType.isEmpty {
            contentType = "application/json"
            req.addValue(contentType, forHTTPHeaderField: "content-type")
        }

        if includeBodyForVerbs.contains(verb) {
            let contentLength: Int = req.httpBody?.count ?? 0
            let xContentSHA256: String = SHA256.hash(data: req.httpBody ?? "".data(using: .utf8)! ).base64

            authHeader.append(#"headers="date (request-target) host content-length content-type x-content-sha256""#)
            signingString.append("date: \(dateString)")
            signingString.append("(request-target): \(verb) \(encodedPath)")
            signingString.append("host: \(req.url?.host ?? "")")
            signingString.append("content-length: \(contentLength)")
            signingString.append("content-type: \(contentType)")
            signingString.append("x-content-sha256: \(xContentSHA256)")

            req.addValue(String(contentLength), forHTTPHeaderField: "content-length")
            req.addValue(xContentSHA256, forHTTPHeaderField: "x-content-sha256")
        } else {
            authHeader.append(#"headers="date (request-target) host""#)
            signingString.append("date: \(dateString)")
            signingString.append("(request-target): \(verb) \(encodedPath)")
            signingString.append("host: \(req.url?.host ?? "")")
        }

        authHeader.append(#"keyId="\#(keyId)""#)
        authHeader.append(#"algorithm="rsa-sha256""#)

        logger.debug("signingString: \n\(signingString)\n----------------\n")
        let dataToSign = signingString.joined(separator: "\n").data(using: .ascii)!
        let signature = try privateKey.signature(for: dataToSign, padding: .insecurePKCS1v1_5)
        let signatureBase64String = signature.rawRepresentation.base64EncodedString()

        authHeader.append(#"signature="\#(signatureBase64String)""#)
        req.addValue(authHeader.joined(separator: ","), forHTTPHeaderField: "Authorization")
    }
}
