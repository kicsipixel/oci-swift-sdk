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

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Configuration for automatic retries of failed service requests.
///
/// Retries use exponential backoff with full jitter: before attempt `n + 1` the
/// client sleeps for a random duration in `0...min(maxDelay, baseDelay * exponentialGrowthFactor^(n-1))`.
/// When the response carries a parseable `Retry-After` header, that value is
/// honored instead of the computed backoff.
///
/// A request is retried when the response status code is in ``retryableStatusCodes``,
/// or when the transport throws a transient connection error (see
/// ``retriesOnConnectionErrors``). Every attempt is signed afresh, so `date`
/// headers stay within OCI's clock-skew window and token-based signers can
/// rotate credentials between attempts.
///
/// The defaults mirror the Python SDK's `DEFAULT_RETRY_STRATEGY`: 8 total
/// attempts, 1 s base delay, 30 s per-sleep cap, and a 600 s cumulative sleep
/// budget. Passing `nil` for a client's `retryConfig` disables retries entirely
/// (the historical behavior, and the Python SDK's default).
public struct RetryConfig: Sendable {
  /// Total number of attempts, including the initial one. Must be at least 1.
  public var maxAttempts: Int
  /// Base delay in seconds used for the exponential backoff calculation.
  public var baseDelay: TimeInterval
  /// Upper bound in seconds for any single backoff sleep.
  public var maxDelay: TimeInterval
  /// Growth factor applied per attempt in the exponential backoff calculation.
  public var exponentialGrowthFactor: Double
  /// Upper bound in seconds for the total time spent sleeping between attempts.
  /// Once the budget is exhausted, the most recent outcome is returned or rethrown.
  public var maxCumulativeDelay: TimeInterval
  /// HTTP status codes that trigger a retry.
  public var retryableStatusCodes: Set<Int>
  /// Whether transient connection errors (timeouts, dropped connections, DNS
  /// failures) thrown by the transport also trigger a retry.
  public var retriesOnConnectionErrors: Bool

  /// A ready-to-use configuration mirroring the Python SDK's default strategy.
  public static let `default` = RetryConfig()

  public init(
    maxAttempts: Int = 8,
    baseDelay: TimeInterval = 1,
    maxDelay: TimeInterval = 30,
    exponentialGrowthFactor: Double = 2,
    maxCumulativeDelay: TimeInterval = 600,
    retryableStatusCodes: Set<Int> = [429, 500, 502, 503, 504],
    retriesOnConnectionErrors: Bool = true
  ) {
    self.maxAttempts = max(1, maxAttempts)
    self.baseDelay = baseDelay
    self.maxDelay = maxDelay
    self.exponentialGrowthFactor = exponentialGrowthFactor
    self.maxCumulativeDelay = maxCumulativeDelay
    self.retryableStatusCodes = retryableStatusCodes
    self.retriesOnConnectionErrors = retriesOnConnectionErrors
  }

  /// Returns the number of seconds to sleep before the attempt following `attempt`
  /// (1-based). A server-provided `Retry-After` value is honored verbatim;
  /// otherwise full jitter is applied over the capped exponential backoff.
  func delay(forAttempt attempt: Int, retryAfter: TimeInterval? = nil) -> TimeInterval {
    if let retryAfter, retryAfter >= 0 {
      return retryAfter
    }
    let exponential = baseDelay * pow(exponentialGrowthFactor, Double(max(0, attempt - 1)))
    let cap = min(maxDelay, exponential)
    guard cap > 0 else { return 0 }
    return Double.random(in: 0...cap)
  }

  /// Parses a `Retry-After` header value in its delta-seconds form (the form OCI
  /// uses). Returns `nil` for HTTP-date or otherwise unparseable values, in which
  /// case the computed backoff applies.
  static func retryAfterSeconds(from value: String) -> TimeInterval? {
    guard let seconds = TimeInterval(value.trimmingCharacters(in: .whitespaces)), seconds >= 0 else {
      return nil
    }
    return seconds
  }

  /// Whether `error` is a transient connection failure worth retrying, mirroring
  /// the Python SDK's timeout/connection-error checkers.
  func isTransient(_ error: Error) -> Bool {
    guard retriesOnConnectionErrors, let urlError = error as? URLError else { return false }
    switch urlError.code {
    case .timedOut, .cannotConnectToHost, .networkConnectionLost, .dnsLookupFailed,
      .cannotFindHost, .notConnectedToInternet, .secureConnectionFailed:
      return true
    default:
      return false
    }
  }
}
