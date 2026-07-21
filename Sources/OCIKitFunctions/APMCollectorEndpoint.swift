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

import Foundation

/// An OCI APM span-ingestion endpoint, retargeted from the legacy Zipkin collector
/// URL the Functions platform injects to the OTLP/HTTP path an OpenTelemetry
/// exporter can post to.
///
/// With tracing enabled on an application and function, the platform sets
/// `OCI_TRACE_COLLECTOR_URL` to its APM domain's Zipkin v2 endpoint:
///
/// ```
/// https://<domain>.apm-agt.<region>.oci.oraclecloud.com/20200101/observations/public-span
///   ?dataFormat=zipkin&dataFormatVersion=2&dataKey=<data key>
/// ```
///
/// Swift has no Zipkin client, but the same APM domain also ingests OTLP/HTTP, so
/// this type rewrites that URL into ``otlpTracesURL`` and lifts the embedded data
/// key into ``dataKeyHeaderValue`` — everything a stock OTLP/HTTP exporter needs:
///
/// ```swift
/// // Tracing off, or the injected URL did not match the documented shape — fall
/// // back to explicit configuration (an APM data key read from Vault, say).
/// let endpoint =
///   context.tracing.collectorEndpoint
///   ?? APMCollectorEndpoint(dataUploadEndpoint: apmDataUploadEndpoint, dataKey: vaultDataKey)
/// // endpoint.otlpTracesURL       -> https://<domain>.../20200101/opentelemetry/public/v1/traces
/// // endpoint.dataKeyHeaderValue  -> "dataKey <data key>" (send as `Authorization`)
/// ```
///
/// APM authenticates span uploads with the data key alone — no OCI request signing,
/// no signer, and no IAM policy are involved on this path.
///
/// Parsing is deliberately defensive. The composition of the injected URL is
/// observed-stable but not contractually promised, so the parsing initializers are
/// failable and return `nil` rather than trapping or guessing whenever the URL
/// does not carry an API version, an `observations/{public-span|private-span}`
/// path, and a non-empty `dataKey` query item. The non-failable initializers cover
/// the fallback: an endpoint composed from explicitly configured values.
public struct APMCollectorEndpoint: Sendable, Equatable {

  /// Which of an APM domain's two span-ingestion paths the collector URL names.
  ///
  /// Public spans are visible to anyone holding the domain's public data key;
  /// private spans require the private key. Functions only ever injects a public
  /// collector URL, but both are parsed.
  public enum Visibility: String, Sendable {
    /// The `public-span` (Zipkin) / `opentelemetry/public` (OTLP) path.
    case publicSpan = "public"
    /// The `private-span` (Zipkin) / `opentelemetry/private` (OTLP) path.
    case privateSpan = "private"
  }

  /// The OTLP/HTTP traces endpoint on the same APM domain, e.g.
  /// `https://<domain>.apm-agt.<region>.oci.oraclecloud.com/20200101/opentelemetry/public/v1/traces`.
  ///
  /// The API version and any path prefix are carried over from the collector URL
  /// rather than hard-coded, so a future version bump retargets automatically.
  public let otlpTracesURL: URL

  /// The APM data key lifted out of the collector URL's `dataKey` query item.
  public let dataKey: String

  /// Whether the collector URL named the public or the private span path.
  public let visibility: Visibility

  /// The value to send as the `Authorization` header when uploading spans:
  /// `dataKey <data key>`.
  public var dataKeyHeaderValue: String {
    "dataKey \(dataKey)"
  }

  /// The query item carrying the APM data key.
  private static let dataKeyQueryItem = "dataKey"

  /// The path segment introducing the legacy Zipkin ingestion paths.
  private static let observationsSegment = "observations"

  /// The path segment introducing the OTLP ingestion paths.
  private static let openTelemetrySegment = "opentelemetry"

  /// The OTLP/HTTP path segments that follow the visibility segment.
  private static let otlpTracesSegments = ["v1", "traces"]

  /// The APM ingestion API version used when composing an endpoint from explicit
  /// configuration — the version the platform's collector URL carries today.
  public static let defaultAPIVersion = "20200101"

  /// Builds an endpoint from an already-composed OTLP/HTTP traces URL.
  ///
  /// Use this when the platform injected no usable collector URL and the full
  /// endpoint is configured explicitly.
  ///
  /// - Parameters:
  ///   - otlpTracesURL: The OTLP/HTTP traces endpoint to post spans to.
  ///   - dataKey: The APM data key to authenticate uploads with.
  ///   - visibility: Which span path `otlpTracesURL` names.
  public init(otlpTracesURL: URL, dataKey: String, visibility: Visibility) {
    self.otlpTracesURL = otlpTracesURL
    self.dataKey = dataKey
    self.visibility = visibility
  }

  /// Builds an endpoint from an APM domain's data-upload endpoint, composing the
  /// OTLP/HTTP traces path onto it.
  ///
  /// This is the fallback ``TracingContext/collectorEndpoint`` points at: with the
  /// domain's `dataUploadEndpoint` and a data key (read from Vault, say) in hand, a
  /// function gets the same endpoint type without re-deriving the OTLP path or the
  /// `Authorization` format.
  ///
  /// - Parameters:
  ///   - dataUploadEndpoint: The APM domain's `dataUploadEndpoint`, e.g.
  ///     `https://<domain>.apm-agt.<region>.oci.oraclecloud.com`.
  ///   - dataKey: The APM data key to authenticate uploads with. It must match
  ///     `visibility` — a public key for ``Visibility/publicSpan``, a private key
  ///     for ``Visibility/privateSpan``.
  ///   - visibility: Which span path to post to. Defaults to
  ///     ``Visibility/publicSpan``, the path Functions itself is given.
  ///   - apiVersion: The ingestion API version segment. Defaults to
  ///     ``defaultAPIVersion``.
  public init(
    dataUploadEndpoint: URL,
    dataKey: String,
    visibility: Visibility = .publicSpan,
    apiVersion: String = APMCollectorEndpoint.defaultAPIVersion
  ) {
    let segments =
      [apiVersion, Self.openTelemetrySegment, visibility.rawValue] + Self.otlpTracesSegments
    let otlpTracesURL = segments.reduce(dataUploadEndpoint) { $0.appending(path: $1) }
    self.init(otlpTracesURL: otlpTracesURL, dataKey: dataKey, visibility: visibility)
  }

  /// Parses a collector URL string, e.g. the value of `OCI_TRACE_COLLECTOR_URL`.
  ///
  /// - Parameter collectorURL: The Zipkin collector URL injected by the platform.
  /// - Returns: `nil` if the string is not a URL, or does not match the documented
  ///   collector-URL shape.
  public init?(collectorURL: String) {
    guard let url = URL(string: collectorURL) else { return nil }
    self.init(collectorURL: url)
  }

  /// Parses a collector URL.
  ///
  /// - Parameter collectorURL: The Zipkin collector URL injected by the platform.
  /// - Returns: `nil` if the URL carries no host, no non-empty `dataKey` query
  ///   item, or no `<version>/observations/{public-span|private-span}` path.
  public init?(collectorURL: URL) {
    guard
      var components = URLComponents(url: collectorURL, resolvingAgainstBaseURL: false),
      components.host?.isEmpty == false,
      let dataKey = components.queryItems?
        .first(where: { $0.name.caseInsensitiveCompare(Self.dataKeyQueryItem) == .orderedSame })?
        .value,
      !dataKey.isEmpty
    else {
      return nil
    }

    // Expected: [<prefix>…, <version>, "observations", "{public|private}-span"].
    // Anything else is an undocumented shape and fails soft.
    let segments = components.path.split(separator: "/").map(String.init)
    guard
      let observations = segments.firstIndex(where: {
        $0.caseInsensitiveCompare(Self.observationsSegment) == .orderedSame
      }),
      observations > 0,
      observations + 1 < segments.count,
      let visibility = Visibility(spanSegment: segments[observations + 1])
    else {
      return nil
    }

    // Everything up to and including the API version is preserved verbatim; only
    // the collector's trailing "observations/<visibility>-span" is rewritten.
    let otlpSegments =
      Array(segments[..<observations]) + [Self.openTelemetrySegment, visibility.rawValue]
      + Self.otlpTracesSegments
    components.path = "/" + otlpSegments.joined(separator: "/")
    components.query = nil
    components.fragment = nil
    guard let otlpTracesURL = components.url else { return nil }

    self.otlpTracesURL = otlpTracesURL
    self.dataKey = dataKey
    self.visibility = visibility
  }
}

extension APMCollectorEndpoint.Visibility {
  /// Maps a legacy Zipkin path segment (`public-span` / `private-span`,
  /// case-insensitively) onto a visibility, or `nil` for anything else.
  init?(spanSegment: String) {
    switch spanSegment.lowercased() {
    case "public-span": self = .publicSpan
    case "private-span": self = .privateSpan
    default: return nil
    }
  }
}
