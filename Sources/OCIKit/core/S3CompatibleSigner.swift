import Foundation

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
import CommonCrypto
#else
import CryptoKit
#endif

// MARK: - DEBUG
fileprivate let debug = true
fileprivate func debugPrint(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    if debug {
        print("SIGV4 DEBUG:", items.map { "\($0)" }.joined(separator: separator), terminator: terminator)
    }
}

// MARK: - Credentials
public struct AWSCredentials {
    public let accessKey: String
    public let secretKey: String
    public let sessionToken: String?

    public init(accessKey: String, secretKey: String, sessionToken: String? = nil) {
        self.accessKey = accessKey
        self.secretKey = secretKey
        self.sessionToken = sessionToken
    }
}

// MARK: - Signer
public final class SigV4Signer {
    private let credentials: AWSCredentials
    private let region: Region
    private let service: String
    private let date: Date

    private static let algorithm = "AWS4-HMAC-SHA256"
    private static let emptyPayloadHash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

    public init(credentials: AWSCredentials, region: Region, service: String = "s3", date: Date = Date()) {
        self.credentials = credentials
        self.region = region
        self.service = service
        self.date = date
    }

    // MARK: - Sign Request
    public func signRequest(_ request: inout URLRequest) throws {
        debugPrint("\n--- SIGN REQUEST START ---")
        debugPrint("URL: \(request.url?.absoluteString ?? "nil")")
        debugPrint("Method: \(request.httpMethod ?? "GET")")

        let timestamp = iso8601Full(date)
        let datestamp = iso8601Date(date)
        debugPrint("Timestamp: \(timestamp)")
        debugPrint("Datestamp: \(datestamp)")

        var headers: [String: String] = [:]
        headers["host"] = request.url?.host ?? ""
        headers["x-amz-date"] = timestamp
        if let token = credentials.sessionToken {
            headers["x-amz-security-token"] = token
        }

        // ALWAYS hash body — OCI requires SHA256, not UNSIGNED-PAYLOAD
        let payloadHash = sha256(request.httpBody ?? Data())
        headers["x-amz-content-sha256"] = payloadHash

        request.allHTTPHeaderFields = headers
        request.setValue("application/xml", forHTTPHeaderField: "Accept")

        debugPrint("Headers (before signing):")
        for (k, v) in headers { debugPrint("  \(k): \(v)") }

        let canonical = try canonicalRequest(from: request, payloadHash: payloadHash, includeBody: true)
        debugPrint("\nCanonical Request:\n\(canonical.request)")

        let credentialScope = "\(datestamp)/\(region.ociShortCode)/\(service)/aws4_request"
        debugPrint("Credential Scope: \(credentialScope)")

        let canonicalHash = sha256(Data(canonical.request.utf8))

        let stringToSign = """
        \(SigV4Signer.algorithm)
        \(timestamp)
        \(credentialScope)
        \(canonicalHash)
        """
        debugPrint("\nString to Sign:\n\(stringToSign)")

        let signingKey = derivedSigningKey(secret: credentials.secretKey, date: datestamp)
        let signature = hmacSHA256(key: signingKey, message: Data(stringToSign.utf8)).hexEncodedString()
        let encodedAccessKey = urlEncodeCredential(credentials.accessKey)

        let auth = """
        \(SigV4Signer.algorithm) Credential=\(encodedAccessKey)/\(credentialScope), \
        SignedHeaders=\(canonical.signedHeaders), \
        Signature=\(signature)
        """
        request.setValue(auth, forHTTPHeaderField: "Authorization")

        debugPrint("\nFinal Authorization Header:\n\(auth)")
        debugPrint("--- SIGN REQUEST END ---\n")
    }

    // MARK: - Canonical Request
    private func canonicalRequest(from request: URLRequest,
                                  payloadHash: String,
                                  includeBody: Bool) throws -> (request: String, signedHeaders: String) {
        guard let url = request.url else { throw SigV4Error.missingURL }

        let method = request.httpMethod?.uppercased() ?? "GET"
        let path = url.path.isEmpty ? "/" : url.path
        let query = canonicalQueryString(from: url)
        let headers = canonicalHeaders(from: request.allHTTPHeaderFields ?? [:])
        let signedHeaders = headers.keys.sorted().joined(separator: ";")

        let headerLines = headers
            .sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value)" }
            .joined(separator: "\n")

        let canonical = """
        \(method)
        \(path)
        \(query)
        \(headerLines)\n
        \n\(signedHeaders)
        \(payloadHash)
        """
        return (canonical, signedHeaders)
    }
private func canonicalHeaders(from headers: [String: String]) -> [String: String] {
var result: [String: String] = [:]
for (k, v) in headers {
    let lower = k.lowercased()
    result[lower] = v
    
    if lower == "accept" {
      continue
    }
    
    result[lower] = v.trimmingCharacters(in: .whitespaces)
}
return result
}


    private func canonicalQueryString(from url: URL) -> String {
        guard let comp = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = comp.queryItems else { return "" }

        return items
            .map { ($0.name, $0.value ?? "") }
            .sorted { $0.0 < $1.0 }
            .map { percentEncode($0) + "=" + percentEncode($1) }
            .joined(separator: "&")
    }

    // MARK: - Crypto
    private func derivedSigningKey(secret: String, date: String) -> Data {
        let kDate = hmacSHA256(key: Data("AWS4\(secret)".utf8), message: Data(date.utf8))
        let kRegion = hmacSHA256(key: kDate, message: Data(region.ociShortCode.utf8))  // fra
        let kService = hmacSHA256(key: kRegion, message: Data(service.utf8))
        let kSigning = hmacSHA256(key: kService, message: Data("aws4_request".utf8))

        debugPrint("Signing Key Steps:")
        debugPrint("  kDate: \(kDate.hexEncodedString())")
        debugPrint("  kRegion (using \(region.ociShortCode)): \(kRegion.hexEncodedString())")
        debugPrint("  kService: \(kService.hexEncodedString())")
        debugPrint("  kSigning: \(kSigning.hexEncodedString())")

        return kSigning
    }

    private func hmacSHA256(key: Data, message: Data) -> Data {
#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        key.withUnsafeBytes { kPtr in
            message.withUnsafeBytes { mPtr in
                CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256),
                       kPtr.baseAddress, key.count,
                       mPtr.baseAddress, message.count,
                       &digest)
            }
        }
        return Data(digest)
#else
        let sym = SymmetricKey(data: key)
        let mac = HMAC<SHA256>.authenticationCode(for: message, using: sym)
        return Data(mac)
#endif
    }

    private func sha256(_ data: Data) -> String {
#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
#else
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
#endif
    }

    // MARK: - Date
    private func iso8601Full(_ date: Date) -> String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        fmt.timeZone = TimeZone(secondsFromGMT: 0)
        return fmt.string(from: date)
    }

    private func iso8601Date(_ date: Date) -> String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withFullDate]
        fmt.timeZone = TimeZone(secondsFromGMT: 0)
        return fmt.string(from: date)
    }

    // MARK: - Encoding
    private func percentEncode(_ string: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "-._~"))
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }

    private func urlEncodeCredential(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "+", with: "%2B")
            .replacingOccurrences(of: "=", with: "%3D")
    }
}

// MARK: - Data → Hex
extension Data {
    func hexEncodedString() -> String {
        return map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Errors
public enum SigV4Error: Error {
    case missingURL
    case invalidURL
    case invalidRequest
}
