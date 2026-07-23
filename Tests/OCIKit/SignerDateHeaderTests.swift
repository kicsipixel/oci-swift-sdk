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
// Hermetic tests for the RFC 1123 `date` header the request signer builds
// (issue #97) — no ~/.oci/config, no credentials, no network. The RSA key is
// generated in-process, so the full signing path can be exercised anywhere
// (CI, fork PRs, offline).
//
// The `date` header is part of the signing string, so it must be the ASCII,
// English, GMT wall-clock representation of the signing instant on EVERY host,
// regardless of the machine's locale or time zone. Before #97 the formatter
// pinned neither, so a non-English locale rendered localized day/month names
// (e.g. "lun., 21 juil. 2026") and a DST-observing host could be an hour off —
// both malform the signed string and produce an undifferentiated HTTP 401.
//

import Foundation
import Testing
import _CryptoExtras

@testable import OCIKit

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite("Signer date header (issue #97)")
struct SignerDateHeaderTests {

  // MARK: - Helpers

  /// Strict RFC 1123 date matcher: ASCII English weekday/month tokens, GMT zone.
  /// A localized string ("lun., 21 juil. 2026 …") fails this by construction.
  private func isRFC1123GMT(_ s: String) -> Bool {
    let pattern =
      #"^(Mon|Tue|Wed|Thu|Fri|Sat|Sun), \d{2} (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) \d{4} \d{2}:\d{2}:\d{2} GMT$"#
    return s.range(of: pattern, options: .regularExpression) != nil
  }

  /// Parse an RFC 1123 GMT string back to an instant with an INDEPENDENT
  /// en_US_POSIX / GMT parser. Round-tripping proves the emitted string both
  /// used English tokens (else this parser rejects it) and encoded the correct
  /// UTC wall-clock instant (else the instant comes back shifted).
  private func parseRFC1123GMT(_ s: String) -> Date? {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: "GMT")
    f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
    return f.date(from: s)
  }

  /// Pull the base64 `signature="…"` value out of the Authorization header.
  private func signatureBase64(from authorization: String) -> String? {
    guard let r = authorization.range(of: #"signature="[^"]+""#, options: .regularExpression) else {
      return nil
    }
    return String(authorization[r].dropFirst(#"signature=""#.count).dropLast())
  }

  // MARK: - The pinned formatter

  @Test("rfc1123DateString renders the exact ASCII English GMT string for known instants")
  func knownInstantsExact() {
    // Ground-truth anchors that do not depend on any hand computation:
    //  • epoch 0 is the canonical "Thu, 01 Jan 1970 00:00:00 GMT".
    //  • epoch 1e9 is the well-known Unix billennium, 01:46:40 UTC on Sunday.
    #expect(
      RequestSigner.rfc1123DateString(from: Date(timeIntervalSince1970: 0))
        == "Thu, 01 Jan 1970 00:00:00 GMT"
    )
    #expect(
      RequestSigner.rfc1123DateString(from: Date(timeIntervalSince1970: 1_000_000_000))
        == "Sun, 09 Sep 2001 01:46:40 GMT"
    )
  }

  @Test(
    "rfc1123DateString is valid, ASCII, and round-trips to the same GMT instant",
    arguments: [
      0.0,
      1_000_000_000.0,  // Sun, 09 Sep 2001 01:46:40 GMT
      1_784_592_000.0,  // a 2026 instant
      1_772_953_200.0,  // 2026 US spring-forward instant (see gmtWallClock)
    ] as [TimeInterval]
  )
  func validAsciiRoundTrip(epoch: TimeInterval) throws {
    let instant = Date(timeIntervalSince1970: epoch)
    let s = RequestSigner.rfc1123DateString(from: instant)

    let isASCII = s.allSatisfy { $0.isASCII }
    #expect(isRFC1123GMT(s), "not a strict ASCII-English RFC 1123 GMT date: \(s)")
    #expect(isASCII, "date header must be ASCII: \(s)")

    let parsed = try #require(parseRFC1123GMT(s), "en_US_POSIX/GMT parser rejected: \(s)")
    #expect(abs(parsed.timeIntervalSince1970 - epoch) < 0.001)
  }

  @Test("rfc1123DateString is GMT wall-clock, immune to host time zone and DST")
  func gmtWallClock() {
    // 2026-03-08 07:00:00 UTC is the instant the US "spring forward" transition
    // fires (02:00 local, second Sunday of March — so it is always a Sunday).
    // Before #97 the code sampled TimeZone.current.secondsFromGMT() and the
    // formatter's .current zone at two different instants, so a DST-observing
    // host could emit a time one hour off around exactly this boundary.
    let instant = Date(timeIntervalSince1970: 1_772_953_200)
    #expect(RequestSigner.rfc1123DateString(from: instant) == "Sun, 08 Mar 2026 07:00:00 GMT")
  }

  // MARK: - The trap that #97 documents

  @Test("an unpinned formatter localizes under a non-English locale — the trap behind #97")
  func unpinnedFormatterLocalizes() {
    // A 2026 July instant, formatted with the pre-#97 recipe (no pinned locale)
    // under a French locale. This is the Apple QA1480 trap: without
    // en_US_POSIX, EEE/MMM render localized day/month names.
    let instant = Date(timeIntervalSince1970: 1_784_592_000)

    let legacy = DateFormatter()
    legacy.locale = Locale(identifier: "fr_FR")
    legacy.timeZone = TimeZone(identifier: "GMT")
    legacy.dateFormat = "EEE, dd MMM yyyy HH:mm:ss"
    let localized = legacy.string(from: instant) + " GMT"

    let pinned = RequestSigner.rfc1123DateString(from: instant)

    // The pinned SDK output is always valid ASCII English regardless of locale.
    let pinnedIsASCII = pinned.allSatisfy { $0.isASCII }
    #expect(isRFC1123GMT(pinned))
    #expect(pinnedIsASCII)

    // If the runtime carries fr_FR locale data (it does on macOS and on the
    // Swift Linux images), the unpinned recipe diverges and is NOT a conforming
    // RFC 1123 GMT date — demonstrating why the SDK must pin the locale. Where
    // the data is absent, DateFormatter falls back to English and there is
    // nothing to demonstrate, so guard the assertion on actual divergence.
    if localized != pinned {
      #expect(
        !isRFC1123GMT(localized),
        "unpinned fr_FR formatter should not conform to RFC 1123: \(localized)"
      )
    }
  }

  // MARK: - The real signing path

  @Test("sign() writes an ASCII RFC 1123 GMT date header whose value is reused in the signed string")
  func signRoundTrip() throws {
    let key = try _RSA.Signing.PrivateKey(keySize: .bits2048)
    let publicKey = key.publicKey

    var req = URLRequest(
      url: URL(
        string: "https://objectstorage.us-ashburn-1.oraclecloud.com/n/mytenancy/b/mybucket/o/myobject"
      )!
    )
    req.httpMethod = "GET"

    try RequestSigner.sign(
      &req,
      with: key,
      keyId: "ocid1.tenancy.oc1..aaaa/ocid1.user.oc1..bbbb/aa:bb:cc"
    )

    // The header itself must be a clean ASCII RFC 1123 GMT date.
    let dateHeader = try #require(req.value(forHTTPHeaderField: "date"))
    let dateHeaderIsASCII = dateHeader.allSatisfy { $0.isASCII }
    #expect(isRFC1123GMT(dateHeader), "malformed date header: \(dateHeader)")
    #expect(dateHeaderIsASCII)

    // Re-derive the signing string for a bodyless GET exactly as the signer
    // does, using the DATE HEADER value. If the signer had signed a different
    // date string than it emitted, this signature would not verify.
    let host = try #require(req.url?.host)
    let path = req.url?.path ?? "/"
    let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
    let signingString = [
      "date: \(dateHeader)",
      "(request-target): get \(encodedPath)",
      "host: \(host)",
    ].joined(separator: "\n")

    let authorization = try #require(req.value(forHTTPHeaderField: "Authorization"))
    let sigBase64 = try #require(signatureBase64(from: authorization))
    let sigData = try #require(Data(base64Encoded: sigBase64))
    let signature = _RSA.Signing.RSASignature(rawRepresentation: sigData)

    #expect(
      publicKey.isValidSignature(
        signature,
        for: signingString.data(using: .ascii)!,
        padding: .insecurePKCS1v1_5
      )
    )
  }
}
