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

/// Tuning knobs for ``OCILogHandler`` and its ``OCILogBatcher``.
///
/// Only ``logId`` is required; every other value has a default derived from the
/// live-verified behavior of the Logging Ingestion service (see
/// ``LoggingIngestClient/putLogs(logId:details:opcRequestId:timestampOpcAgentProcessing:)``
/// for the underlying limits).
///
/// ## Example
/// ```swift
/// var configuration = OCILogHandlerConfiguration(logId: "ocid1.log.oc1.phx.EXAMPLE")
/// configuration.type = "com.example.orders"
/// configuration.subject = "order-service"
/// configuration.flushInterval = 2
/// ```
public struct OCILogHandlerConfiguration: Sendable {

  // MARK: - Defaults

  /// The default ``type`` stamped onto every emitted batch. Override it with a
  /// value that identifies the application, e.g. `"com.example.orders"`.
  public static let defaultType = "oci-swift-sdk.application"

  /// The default ``source``: this machine's hostname, matching what the OCI
  /// Logging agent reports for file-tailed logs.
  public static var defaultSource: String { ProcessInfo.processInfo.hostName }

  /// The default interval, in seconds, between automatic flushes.
  public static let defaultFlushInterval: TimeInterval = 5

  /// The default buffered-payload size that triggers an immediate flush: 1 MiB.
  ///
  /// The service accepts far larger payloads (1 GiB requests were verified to
  /// return HTTP 200 with no silent drops), so this bound is an ergonomics
  /// choice — it caps retry amplification and per-flush upload latency.
  public static let defaultFlushSizeThreshold = 1 << 20

  /// The default number of records held in the hand-off buffer between the
  /// synchronous `log(...)` hot path and the batcher: 10,000.
  public static let defaultBufferCapacity = 10_000

  /// The default per-entry length limit, a little under the service's 10,000-character
  /// truncation point. Longer messages are split across consecutive entries.
  public static let defaultMaxEntryLength = 9_900

  /// The hard limit the service applies: any `data` longer than this is silently
  /// truncated to exactly 10,000 characters ending in `...` (live-verified).
  public static let serviceEntryLengthLimit = 10_000

  /// The logger labels whose records are always dropped instead of being shipped.
  ///
  /// `"OCIKit"` is the label of the SDK's own global ``logger``, which the request
  /// signer writes to on every signing pass. Shipping those records through this
  /// handler would make each flush generate more records to flush — the recursion
  /// this handler is built to avoid.
  ///
  /// These labels are mandatory: ``init(logId:source:type:subject:flushInterval:flushSizeThreshold:bufferCapacity:maxEntryLength:requestTimeout:retryConfig:excludedLoggerLabels:)``
  /// unions them into ``excludedLoggerLabels``, and
  /// ``OCILogBatcher/isExcluded(loggerLabel:)`` re-checks them, so they cannot be
  /// removed. See ``excludedLoggerLabels``.
  public static let defaultExcludedLoggerLabels: Set<String> = ["OCIKit"]

  /// The default number of seconds a single `PutLogs` attempt may take: 10.
  ///
  /// `URLSession`'s own default is 60 seconds, and a timeout is retryable — so
  /// without a tighter bound one unreachable endpoint could hold
  /// ``OCILogBatcher/shutdown()`` for minutes.
  public static let defaultRequestTimeout: TimeInterval = 10

  /// The default retry policy for a flush: deliberately small and bounded.
  ///
  /// A flush must fail fast rather than hold a slot for minutes — the batcher
  /// keeps at most one `PutLogs` in flight, so a long retry budget would stall
  /// every subsequent flush and overflow the hand-off buffer. A batch whose
  /// retries are exhausted is put back in the buffer for a later flush rather
  /// than discarded: buffered records do not go stale (the service accepts
  /// entries as old as the log's retention window), so dropping is driven by
  /// capacity, never by age.
  public static let defaultRetryConfig = RetryConfig(
    maxAttempts: 3,
    baseDelay: 0.5,
    maxDelay: 5,
    maxCumulativeDelay: 10
  )

  // MARK: - Stored configuration

  /// The OCID of the custom log to ingest into. Required.
  ///
  /// The log group and the log are control-plane resources: create them with
  /// Terraform, the OCI Console, or another SDK, and pass the log's OCID here.
  public var logId: String

  /// The ``LogEntryBatch/source`` stamped onto every emitted batch — typically
  /// the hostname or instance name. Defaults to ``defaultSource``.
  public var source: String

  /// The ``LogEntryBatch/type`` stamped onto every emitted batch.
  /// Defaults to ``defaultType``.
  public var type: String

  /// The optional ``LogEntryBatch/subject`` stamped onto every emitted batch —
  /// the sub-resource the events came from. Defaults to `nil`.
  public var subject: String?

  /// How long the batcher waits, in seconds, before flushing a non-empty buffer.
  ///
  /// Defaults to ``defaultFlushInterval``. Zero — or any negative value, which is
  /// clamped to zero — disables interval flushing, leaving only
  /// ``flushSizeThreshold`` and explicit ``OCILogBatcher/flush()`` calls.
  public var flushInterval: TimeInterval

  /// The buffered payload size, in UTF-8 bytes, that triggers an immediate flush.
  /// Defaults to ``defaultFlushSizeThreshold``.
  public var flushSizeThreshold: Int

  /// How many records the hand-off buffer holds before it starts dropping.
  ///
  /// The buffer keeps the **oldest** records; once it is full, newly logged
  /// records are discarded and counted in
  /// ``OCILogHandlerStatistics/dropped``. Defaults to ``defaultBufferCapacity``.
  public var bufferCapacity: Int

  /// The maximum number of characters in a single ``LogEntry/data``.
  ///
  /// Longer messages are split across consecutive entries so nothing is lost to
  /// the service's silent truncation. Values outside `1...`
  /// ``serviceEntryLengthLimit`` are clamped into that range — both here and
  /// again where the batcher splits a record, so mutating this property after
  /// the configuration was created cannot reopen the truncation hole.
  /// Defaults to ``defaultMaxEntryLength``.
  public var maxEntryLength: Int

  /// How many seconds a single `PutLogs` attempt may take before it is treated
  /// as a (retryable) timeout.
  ///
  /// Defaults to ``defaultRequestTimeout``. Zero — or any negative value, which
  /// is clamped to zero — leaves the transport's own timeout in place, which for
  /// `URLSession` is 60 seconds per attempt.
  public var requestTimeout: TimeInterval

  /// The retry policy applied to each `PutLogs` flush. Defaults to
  /// ``defaultRetryConfig``; `nil` performs a single attempt per flush.
  ///
  /// Together with ``requestTimeout`` this bounds how long a flush — and so
  /// ``OCILogBatcher/shutdown()`` — can take:
  /// `maxAttempts × requestTimeout + maxCumulativeDelay`.
  public var retryConfig: RetryConfig?

  /// Logger labels whose records this handler drops instead of shipping.
  ///
  /// This is the label-based half of the recursion guard, for code that logs
  /// through the *bootstrapped* system outside a flush — the SDK's own global
  /// ``logger``, for instance. (Logging from inside a flush is caught by
  /// ``OCILogBatcher/isFlushing`` regardless of label, and the batcher's own
  /// client bypasses the bootstrapped system entirely.)
  ///
  /// A caller-supplied set is *added* to ``defaultExcludedLoggerLabels`` rather
  /// than replacing it, so silencing one noisy label cannot accidentally
  /// un-silence the SDK's own.
  public var excludedLoggerLabels: Set<String>

  /// Creates a configuration.
  ///
  /// - Parameters:
  ///   - logId: The OCID of the custom log to ingest into.
  ///   - source: The batch source. Defaults to this machine's hostname.
  ///   - type: The batch type. Defaults to ``defaultType``.
  ///   - subject: The batch subject. Defaults to `nil`.
  ///   - flushInterval: How many seconds to wait before flushing a non-empty
  ///     buffer. Negative values are clamped to zero, which disables interval flushing.
  ///   - flushSizeThreshold: Buffered UTF-8 bytes that trigger an immediate flush.
  ///     Values below 1 are clamped to 1.
  ///   - bufferCapacity: Hand-off buffer depth in records. Values below 1 are clamped to 1.
  ///   - maxEntryLength: Maximum characters per entry. Clamped to at least 1 and
  ///     at most ``serviceEntryLengthLimit``.
  ///   - requestTimeout: Seconds allowed per `PutLogs` attempt. Negative values are
  ///     clamped to zero, which leaves the transport's own timeout in place.
  ///   - retryConfig: Retry policy for a flush; `nil` disables retries.
  ///   - excludedLoggerLabels: Logger labels to drop, unioned with
  ///     ``defaultExcludedLoggerLabels``. See ``excludedLoggerLabels``.
  public init(
    logId: String,
    source: String = OCILogHandlerConfiguration.defaultSource,
    type: String = OCILogHandlerConfiguration.defaultType,
    subject: String? = nil,
    flushInterval: TimeInterval = OCILogHandlerConfiguration.defaultFlushInterval,
    flushSizeThreshold: Int = OCILogHandlerConfiguration.defaultFlushSizeThreshold,
    bufferCapacity: Int = OCILogHandlerConfiguration.defaultBufferCapacity,
    maxEntryLength: Int = OCILogHandlerConfiguration.defaultMaxEntryLength,
    requestTimeout: TimeInterval = OCILogHandlerConfiguration.defaultRequestTimeout,
    retryConfig: RetryConfig? = OCILogHandlerConfiguration.defaultRetryConfig,
    excludedLoggerLabels: Set<String> = OCILogHandlerConfiguration.defaultExcludedLoggerLabels
  ) {
    self.logId = logId
    self.source = source
    self.type = type
    self.subject = subject
    self.flushInterval = max(0, flushInterval)
    self.flushSizeThreshold = max(1, flushSizeThreshold)
    self.bufferCapacity = max(1, bufferCapacity)
    self.maxEntryLength = min(Self.serviceEntryLengthLimit, max(1, maxEntryLength))
    self.requestTimeout = max(0, requestTimeout)
    self.retryConfig = retryConfig
    self.excludedLoggerLabels = excludedLoggerLabels.union(Self.defaultExcludedLoggerLabels)
  }
}
