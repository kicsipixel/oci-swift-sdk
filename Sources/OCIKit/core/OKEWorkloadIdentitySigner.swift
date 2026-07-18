//===----------------------------------------------------------------------===//
//
// This source file is part of the oci-swift-sdk open source project
//
// Copyright (c) 2026 Ilia Sazonov and the oci-swift-sdk project authors
// Licensed under MIT License
//
// See LICENSE for license information
// See CONTRIBUTORS.md for the list of oci-swift-sdk project authors
//
// SPDX-License-Identifier: MIT License
//
//===----------------------------------------------------------------------===//
//
// Implements OCI **OKE Workload Identity** authentication, mirroring
// `oci/auth/signers/oke_workload_identity_resource_principal_signer.py`
// (`OkeWorkloadIdentityResourcePrincipalSigner`) from the Python SDK.
//
// OKE Workload Identity lets a pod running in an OCI Kubernetes Engine (OKE)
// cluster authenticate to OCI services using the pod's Kubernetes service
// account — no API key, no config file. Unlike Resource Principals v2.2
// (Functions / Container Instances), where the hosting service injects a ready
// RPST + private key into the container's environment, OKE performs a **runtime
// token exchange**:
//
//   1. The SDK generates an ephemeral RSA keypair.
//   2. It POSTs the public key (`{"podKey": <SPKI>}`) to the in-cluster
//      "proxymux" endpoint — `https://$KUBERNETES_SERVICE_HOST:12250/resourcePrincipalSessionTokens`
//      — authenticated with the pod's service-account bearer token.
//   3. The endpoint returns a base64-wrapped `{"token":"ST$<rpst>"}`.
//   4. Requests are then signed with keyId `ST$<rpst>` and the ephemeral key,
//      exactly like every other `SecurityTokenSigner`.
//
// The ephemeral key is regenerated on every refresh, and the service-account
// token is re-read from disk each time so a rotated token is picked up.
//
// ## Sync / async design
//
// The token exchange is a network round-trip, but ``Signer/sign(_:)`` is
// synchronous. To honor the project's "async/await throughout, never block"
// rule, this signer decouples the two and guards its cache with a `Mutex`
// (`Synchronization`) — whose `withLock` is safe from async contexts — rather
// than a blocking `NSLock`/`DispatchSemaphore`:
//
//   - ``fromEnvironment(transport:logger:_:)`` is `async` and performs the first
//     exchange eagerly, so the returned signer is ready to sign.
//   - ``refresh()`` / ``refreshIfNeeded()`` are `async` and perform the exchange.
//     Concurrent refreshes are coalesced into a single in-flight exchange.
//   - ``sign(_:)`` is synchronous and uses only cached material. When the cached
//     RPST is past its half-life it schedules a **non-blocking** background
//     refresh so subsequent requests pick up a fresh token, but it never blocks.
//
// Long-running servers should call ``refreshIfNeeded()`` at the start of each
// logical operation (see the `swift-oke` example) so the token never fully
// expires between requests.
//
// ## TLS to the proxymux
//
// The proxymux TLS certificate is signed by the **in-cluster Kubernetes CA**
// (`/var/run/secrets/kubernetes.io/serviceaccount/ca.crt`, override
// `OCI_KUBERNETES_SERVICE_ACCOUNT_CERT_PATH`), not a public CA. `URLSession`
// cannot pin a custom CA in-process (no API on Linux; needs the forbidden
// `Security` framework on Apple), so this signer takes an **injected transport**
// and leaves the CA-pinning transport to the caller.
//
// The batteries-included path is the **`OCIKitWorkloadIdentity`** product:
// `OKEWorkloadIdentitySigner.fromWorkloadIdentity()` builds an AsyncHTTPClient +
// NIOSSL (BoringSSL) transport that pins ``caCertPath`` in-process — matching
// exactly what the Java/Python/Go SDKs do (no OS-trust-store install, no cluster
// step). That transport lives in the opt-in `OCIKitWorkloadIdentity` product so
// non-OKE consumers never pull the swift-nio dependency graph. Advanced callers
// can instead pass any ``HTTPClient`` to ``fromEnvironment(transport:logger:_:)``
// (e.g. ``HTTPClient/live`` when the cluster CA is already in the OS trust store).
//

import Crypto
import Foundation
import Logging
import Synchronization
import _CryptoExtras

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

// MARK: - Errors

/// Errors raised while constructing or using an ``OKEWorkloadIdentitySigner``.
public enum OKEWorkloadIdentityError: Error, LocalizedError, Equatable {
  /// `KUBERNETES_SERVICE_HOST` is not set — the code is not running in a pod.
  case serviceHostNotDefined
  /// The service-account token file could not be read from disk.
  case serviceAccountTokenReadFailed(String)
  /// The service-account token has no `exp` claim or has already expired.
  case serviceAccountTokenExpired
  /// The proxymux returned a non-2xx status. `403` typically means the cluster
  /// is not an *enhanced* OKE cluster (a prerequisite for workload identity).
  case tokenExchangeFailed(status: Int, message: String)
  /// The proxymux response could not be base64/JSON-decoded into an RPST.
  case malformedTokenResponse(String)
  /// The signer has no cached token yet — call ``OKEWorkloadIdentitySigner/refresh()``
  /// (or build it with ``OKEWorkloadIdentitySigner/fromEnvironment(transport:logger:_:)``,
  /// which primes it) before signing.
  case notPrimed
  /// The freshly generated ephemeral key could not be produced.
  case keyGenerationFailed

  public var errorDescription: String? {
    switch self {
    case .serviceHostNotDefined:
      return
        "KUBERNETES_SERVICE_HOST is not defined. OKE Workload Identity authentication can only be used inside an OKE pod."
    case .serviceAccountTokenReadFailed(let path):
      return "Failed to read the Kubernetes service account token from: \(path)"
    case .serviceAccountTokenExpired:
      return "The Kubernetes service account token is missing an exp claim or has expired."
    case .tokenExchangeFailed(let status, let message):
      if status == 403 {
        return
          "OKE Workload Identity token exchange failed (HTTP 403). Please ensure the cluster type is enhanced. \(message)"
      }
      return "OKE Workload Identity token exchange failed (HTTP \(status)). \(message)"
    case .malformedTokenResponse(let detail):
      return "The proxymux response could not be decoded into a resource principal session token: \(detail)"
    case .notPrimed:
      return "The OKE Workload Identity signer has no cached token yet; call refresh() before signing."
    case .keyGenerationFailed:
      return "Failed to generate the ephemeral session key for OKE Workload Identity."
    }
  }
}

// MARK: - Environment variable names & defaults

/// The exact environment-variable names and default paths for OKE Workload Identity.
enum OKEWorkloadIdentityEnv {
  /// Standard Kubernetes-injected host of the API server / proxymux.
  static let serviceHost = "KUBERNETES_SERVICE_HOST"
  /// Optional override for the CA cert path used to verify the proxymux TLS cert.
  static let serviceAccountCertPath = "OCI_KUBERNETES_SERVICE_ACCOUNT_CERT_PATH"
  /// Region id — shared with Resource Principals v2.2.
  static let region = "OCI_RESOURCE_PRINCIPAL_REGION"

  /// Fixed proxymux service port.
  static let proxymuxPort = "12250"
  /// Default in-pod service-account token path.
  static let defaultServiceAccountTokenPath = "/var/run/secrets/kubernetes.io/serviceaccount/token"
  /// Default in-pod cluster CA cert path.
  static let defaultServiceAccountCertPath = "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
}

// MARK: - Service-account token source

/// Where the Kubernetes service-account (SA) token comes from.
///
/// The default OKE deployment mounts the SA token at a well-known path; the
/// token is re-read from disk on every refresh so a rotated token is picked up.
/// A literal token can be supplied instead (re-validated, but never re-read).
enum ServiceAccountTokenSource: Equatable, Sendable {
  /// Read the token from this file path on each refresh.
  case file(String)
  /// Use this literal token value.
  case value(String)
}

// MARK: - OKEWorkloadIdentitySigner

/// A ``RefreshableSigner`` that authenticates using OCI OKE Workload Identity.
///
/// The batteries-included entry point is `fromWorkloadIdentity()` in the
/// `OCIKitWorkloadIdentity` product, which supplies an in-process CA-pinning
/// transport for the proxymux exchange. This core type takes an **injected**
/// transport; see ``fromEnvironment(transport:logger:_:)`` for advanced use.
///
/// ## Example
/// ```swift
/// // Inside an OKE pod whose service account is mapped to an OCI dynamic group:
/// import OCIKit
/// import OCIKitWorkloadIdentity
///
/// let signer = try await OKEWorkloadIdentitySigner.fromWorkloadIdentity()
/// let client = try ObjectStorageClient(region: .fra, signer: signer)
///
/// // In a long-running server, keep the token fresh per request:
/// try await signer.refreshIfNeeded()
/// let data = try await client.getObject(namespaceName: ns, bucketName: b, objectName: o)
/// ```
public final class OKEWorkloadIdentitySigner: RefreshableSigner {
  /// The full proxymux token-exchange endpoint.
  let proxymuxEndpoint: URL
  /// Where the SA token is read from.
  let saTokenSource: ServiceAccountTokenSource
  /// The CA cert path used to verify the proxymux TLS cert. Stored for callers
  /// that inject a CA-pinning transport; the default `URLSession` transport
  /// cannot pin it in-process and relies on the OS trust store instead.
  public let caCertPath: String
  /// The region id reported by `OCI_RESOURCE_PRINCIPAL_REGION`, if any.
  public let region: String?

  private let transport: HTTPClient
  private let logger: Logger

  /// Seconds before `exp` used as the refresh threshold when the RPST carries no
  /// `iat` claim (so a half-life cannot be computed).
  private static let fallbackJitterSeconds = 60

  /// All mutable state, guarded by a `Mutex` (async-safe scoped locking).
  private struct State {
    var token: String?
    var key: _RSA.Signing.PrivateKey?
    var issuedAt: Int?
    var expiry: Int?
    /// The in-flight refresh, if any; used to coalesce concurrent refreshes.
    var inFlight: Task<Void, Error>?
  }
  private let state = Mutex(State())

  // MARK: Designated init

  init(
    proxymuxEndpoint: URL,
    saTokenSource: ServiceAccountTokenSource,
    caCertPath: String,
    region: String?,
    transport: HTTPClient,
    logger: Logger
  ) {
    self.proxymuxEndpoint = proxymuxEndpoint
    self.saTokenSource = saTokenSource
    self.caCertPath = caCertPath
    self.region = region
    self.transport = transport
    self.logger = logger
  }

  // MARK: Public constructors

  /// Builds a signer from the OKE Workload Identity environment and performs the
  /// first token exchange so the returned signer is immediately usable.
  ///
  /// The `transport` is **required** and must be able to verify the proxymux TLS
  /// certificate against the cluster CA. For the batteries-included, in-process
  /// CA-pinning transport, use `OKEWorkloadIdentitySigner.fromWorkloadIdentity()`
  /// from the `OCIKitWorkloadIdentity` product instead of calling this directly.
  ///
  /// - Parameters:
  ///   - transport: The HTTP transport used for the proxymux exchange. Pass a
  ///     CA-pinning transport (see ``caCertPath``), or ``HTTPClient/live``
  ///     (`URLSession`) only when the cluster CA is already in the OS trust store.
  ///   - logger: Logger for diagnostics.
  ///   - environment: The environment to read (defaults to the process
  ///     environment). Injectable for testing.
  /// - Throws: ``OKEWorkloadIdentityError`` when required environment values are
  ///   absent or the initial exchange fails.
  public static func fromEnvironment(
    transport: HTTPClient,
    logger: Logger = Logger(label: "OKEWorkloadIdentitySigner"),
    _ environment: [String: String] = ProcessInfo.processInfo.environment
  ) async throws -> OKEWorkloadIdentitySigner {
    let signer = try make(transport: transport, logger: logger, environment: environment)
    // Fail fast if the environment/cluster is misconfigured, rather than at first request.
    try await signer.refresh()
    return signer
  }

  /// Resolves the CA cert path used to verify the proxymux TLS certificate:
  /// `OCI_KUBERNETES_SERVICE_ACCOUNT_CERT_PATH` if set, else the standard
  /// in-pod path `/var/run/secrets/kubernetes.io/serviceaccount/ca.crt`.
  ///
  /// Exposed so a CA-pinning transport (e.g. in `OCIKitWorkloadIdentity`) can
  /// resolve the same path this signer reports via ``caCertPath``.
  public static func serviceAccountCertPath(
    fromEnvironment environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> String {
    environment[OKEWorkloadIdentityEnv.serviceAccountCertPath].flatMap { $0.isEmpty ? nil : $0 }
      ?? OKEWorkloadIdentityEnv.defaultServiceAccountCertPath
  }

  /// Builds a signer from the environment **without** performing the initial
  /// exchange. Useful when the caller wants to control when the first network
  /// call happens. Call ``refresh()`` before the first ``sign(_:)``.
  static func make(
    transport: HTTPClient,
    logger: Logger = Logger(label: "OKEWorkloadIdentitySigner"),
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) throws -> OKEWorkloadIdentitySigner {
    guard let host = environment[OKEWorkloadIdentityEnv.serviceHost], !host.isEmpty else {
      throw OKEWorkloadIdentityError.serviceHostNotDefined
    }

    guard let endpoint = Self.makeProxymuxEndpoint(host: host) else {
      throw OKEWorkloadIdentityError.serviceHostNotDefined
    }

    return OKEWorkloadIdentitySigner(
      proxymuxEndpoint: endpoint,
      saTokenSource: .file(OKEWorkloadIdentityEnv.defaultServiceAccountTokenPath),
      caCertPath: serviceAccountCertPath(fromEnvironment: environment),
      region: environment[OKEWorkloadIdentityEnv.region].flatMap { $0.isEmpty ? nil : $0 },
      transport: transport,
      logger: logger
    )
  }

  /// Composes the proxymux endpoint URL from the Kubernetes service host.
  static func makeProxymuxEndpoint(host: String) -> URL? {
    URL(string: "https://\(host):\(OKEWorkloadIdentityEnv.proxymuxPort)/resourcePrincipalSessionTokens")
  }

  // MARK: Signer

  public func sign(_ req: inout URLRequest) throws {
    let now = Int(Date().timeIntervalSince1970)
    let snapshot: (token: String, key: _RSA.Signing.PrivateKey, valid: Bool)? = state.withLock { s in
      guard let token = s.token, let key = s.key else { return nil }
      return (token, key, Self.isValid(s, now: now))
    }
    guard let snapshot else { throw OKEWorkloadIdentityError.notPrimed }

    // Past half-life: warm the cache for the next request without blocking this one.
    if !snapshot.valid {
      scheduleBackgroundRefresh()
    }
    try SecurityTokenSigner(securityToken: snapshot.token, privateKey: snapshot.key).sign(&req)
  }

  // MARK: Refresh

  /// Marks the cache stale and schedules a non-blocking background refresh, then
  /// returns immediately. Called by ``HTTPClient/send(_:signer:retry:logger:)``
  /// after a `401`. Because the exchange is asynchronous, the refresh may not
  /// have completed by the time the caller's single immediate retry re-signs;
  /// the recovered token is picked up by the next request. For guaranteed
  /// freshness, `await` ``refreshIfNeeded()`` before the operation.
  public func forceRefresh() throws {
    state.withLock { $0.expiry = 0 }  // force isValid -> false
    scheduleBackgroundRefresh()
  }

  /// Refreshes the token only if the cache is empty or past its half-life.
  public func refreshIfNeeded() async throws {
    let now = Int(Date().timeIntervalSince1970)
    let valid = state.withLock { s in s.token != nil && s.key != nil && Self.isValid(s, now: now) }
    if valid { return }
    try await refresh()
  }

  /// Performs (or joins an in-flight) token exchange with the proxymux and
  /// updates the cached RPST + ephemeral key.
  public func refresh() async throws {
    let task: Task<Void, Error> = state.withLock { s in
      if let existing = s.inFlight { return existing }
      let created = Task { [self] in
        defer { state.withLock { $0.inFlight = nil } }
        try await performRefresh()
      }
      s.inFlight = created
      return created
    }
    try await task.value
  }

  private func performRefresh() async throws {
    // 1. Fresh ephemeral RSA-2048 keypair on every refresh (matches Python).
    guard let key = try? _RSA.Signing.PrivateKey(keySize: .bits2048) else {
      throw OKEWorkloadIdentityError.keyGenerationFailed
    }
    let podKey = Self.sanitizedPodKey(fromSPKIPEM: key.publicKey.pemRepresentation)

    // 2. Read + validate the SA token (re-read from disk each refresh).
    let saToken = try resolveServiceAccountToken()

    // 3. Build and send the exchange request through the injected transport.
    let request = Self.buildTokenExchangeRequest(
      endpoint: proxymuxEndpoint,
      podKey: podKey,
      saToken: saToken,
      opcRequestId: Self.generateOpcRequestId()
    )
    logger.debug("OKE workload identity: exchanging pod key at \(proxymuxEndpoint.absoluteString)")
    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await transport.data(request)
    }
    catch {
      throw OKEWorkloadIdentityError.tokenExchangeFailed(status: -1, message: String(describing: error))
    }

    // 4. Check status, decode RPST, and cache.
    guard let http = response as? HTTPURLResponse else {
      throw OKEWorkloadIdentityError.tokenExchangeFailed(status: -1, message: "Non-HTTP response")
    }
    guard (200..<300).contains(http.statusCode) else {
      let body = String(data: data, encoding: .utf8) ?? ""
      throw OKEWorkloadIdentityError.tokenExchangeFailed(status: http.statusCode, message: body)
    }

    let rpst = try Self.decodeRPST(fromResponseBody: data)
    let claims = OKEWorkloadIdentityToken.issuedAndExpiry(of: rpst)

    state.withLock { s in
      s.token = rpst
      s.key = key
      s.issuedAt = claims.issuedAt
      s.expiry = claims.expiry
    }
    logger.debug("OKE workload identity: obtained RPST (exp=\(claims.expiry.map(String.init) ?? "nil"))")
  }

  /// Fires a background refresh (coalesced by ``refresh()``). Non-blocking.
  private func scheduleBackgroundRefresh() {
    Task { [self] in try? await refresh() }
  }

  /// Reads and validates the service-account token, re-reading files each call.
  private func resolveServiceAccountToken() throws -> String {
    let raw: String
    switch saTokenSource {
    case .value(let v):
      raw = v
    case .file(let path):
      guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
        throw OKEWorkloadIdentityError.serviceAccountTokenReadFailed(path)
      }
      raw = contents
    }
    let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !token.isEmpty else {
      throw OKEWorkloadIdentityError.serviceAccountTokenReadFailed(String(describing: saTokenSource))
    }
    guard OKEWorkloadIdentityToken.isUnexpired(token, now: Int(Date().timeIntervalSince1970)) else {
      throw OKEWorkloadIdentityError.serviceAccountTokenExpired
    }
    return token
  }

  /// Whether the cached token is still within its half-life.
  private static func isValid(_ s: State, now: Int) -> Bool {
    guard s.token != nil, s.key != nil else { return false }
    guard let exp = s.expiry else { return true }  // no exp to evaluate: keep it
    let threshold: Int
    if let iat = s.issuedAt, exp > iat {
      threshold = exp - (exp - iat) / 2  // midpoint of the validity window
    }
    else {
      threshold = exp - fallbackJitterSeconds
    }
    return now < threshold
  }
}

// MARK: - Wire helpers (pure, testable)

extension OKEWorkloadIdentitySigner {
  /// Serializes an SPKI PEM public key into the single-line `podKey` value the
  /// proxymux expects: header/footer lines removed and all newlines stripped.
  static func sanitizedPodKey(fromSPKIPEM pem: String) -> String {
    pem
      .replacing("-----BEGIN PUBLIC KEY-----", with: "")
      .replacing("-----END PUBLIC KEY-----", with: "")
      .replacing("-----BEGIN CERTIFICATE-----", with: "")
      .replacing("-----END CERTIFICATE-----", with: "")
      .replacing("\r", with: "")
      .replacing("\n", with: "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Builds the proxymux token-exchange request.
  static func buildTokenExchangeRequest(
    endpoint: URL,
    podKey: String,
    saToken: String,
    opcRequestId: String
  ) -> URLRequest {
    var req = URLRequest(url: endpoint)
    req.httpMethod = "POST"
    // JSONSerialization with a single string value is deterministic and avoids
    // depending on Encodable key ordering.
    req.httpBody = try? JSONSerialization.data(withJSONObject: ["podKey": podKey])
    req.setValue("Bearer \(saToken)", forHTTPHeaderField: "Authorization")
    req.setValue("application/json", forHTTPHeaderField: "Content-type")
    req.setValue(opcRequestId, forHTTPHeaderField: "opc-request-id")
    return req
  }

  /// Decodes the proxymux response body — base64 of `{"token":"ST$<rpst>"}` —
  /// into the bare RPST (with the `ST$` prefix removed).
  static func decodeRPST(fromResponseBody data: Data) throws -> String {
    guard
      let base64String = String(data: data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines),
      let decoded = Data(base64Encoded: base64String),
      let json = String(data: decoded, encoding: .utf8)
    else {
      throw OKEWorkloadIdentityError.malformedTokenResponse("body is not base64-of-UTF8")
    }
    guard json.contains("token"),
      let jsonData = json.data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
      let tokenValue = object["token"] as? String
    else {
      throw OKEWorkloadIdentityError.malformedTokenResponse("missing token field")
    }
    // The wire value is prefixed with "ST$"; the SecurityTokenSigner re-adds it.
    if tokenValue.hasPrefix("ST$") {
      return String(tokenValue.dropFirst(3))
    }
    return tokenValue
  }

  /// Generates an `opc-request-id`: three 16-byte random hex segments joined by
  /// `/`, matching the Python SDK's format.
  static func generateOpcRequestId() -> String {
    func segment() -> String {
      (0..<16).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
    }
    return "\(segment())/\(segment())/\(segment())"
  }
}

// MARK: - JWT parsing (no signature verification)

/// Minimal JWT reader for the RPST and the SA token. Like the Python SDK, the
/// SDK only needs `iat`/`exp` and does **not** verify the JWT signature.
enum OKEWorkloadIdentityToken {
  /// Returns `(iat, exp)` epoch-second claims, either `nil` if absent/unparseable.
  static func issuedAndExpiry(of token: String) -> (issuedAt: Int?, expiry: Int?) {
    guard let claims = payload(of: token) else { return (nil, nil) }
    return (intClaim(claims["iat"]), intClaim(claims["exp"]))
  }

  /// Whether `token` has an `exp` claim that is still in the future.
  static func isUnexpired(_ token: String, now: Int) -> Bool {
    guard let claims = payload(of: token), let exp = intClaim(claims["exp"]) else { return false }
    return now < exp
  }

  private static func intClaim(_ value: Any?) -> Int? {
    if let i = value as? Int { return i }
    if let d = value as? Double { return Int(d) }
    return nil
  }

  private static func payload(of token: String) -> [String: Any]? {
    let parts = token.split(separator: ".")
    guard parts.count >= 2,
      let data = base64URLDecode(String(parts[1])),
      let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    else {
      return nil
    }
    return object
  }

  /// Decodes a base64url JWT segment (base64url, no padding).
  static func base64URLDecode(_ string: String) -> Data? {
    var base64 =
      string
      .replacing("-", with: "+")
      .replacing("_", with: "/")
    let remainder = base64.count % 4
    if remainder > 0 {
      base64 += String(repeating: "=", count: 4 - remainder)
    }
    return Data(base64Encoded: base64)
  }
}
