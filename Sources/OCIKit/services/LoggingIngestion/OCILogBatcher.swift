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
// The asynchronous half of the OCI swift-log backend. ``OCILogHandler`` renders
// records and hands them off; this actor batches them and uploads them with
// `PutLogs`.
//
// ## Why a stream, and not a task per record
//
// `LogHandler.log(...)` is synchronous and sits on the caller's hot path, so it
// can neither `await` nor block. Spawning an unstructured `Task` per record
// would allocate per record, create an unbounded number of tasks under load, and
// lose ordering. Instead the handler yields into a bounded `AsyncStream`:
// `yield` is synchronous and `Sendable`-safe, `.bufferingOldest(capacity)`
// supplies the bounded buffer and the overflow-drop policy for free, and the
// yield result tells the handler when a record was dropped.
//
// This actor is that stream's single consumer. One long-lived drain task — owned
// here and cancelled deterministically in ``OCILogBatcher/shutdown()`` —
// accumulates entries and flushes on a size threshold, and a second task flushes
// on an interval tick. Concurrent flushes are coalesced so at most one `PutLogs`
// is ever in flight (the `OKEWorkloadIdentitySigner` idiom).
//

import Foundation
import Logging
import Synchronization

/// Batches rendered log records and ships them to OCI Logging with `PutLogs`.
///
/// One batcher backs any number of ``OCILogHandler`` values — swift-log builds a
/// handler per logger label, and they all share the batcher passed to
/// `LoggingSystem.bootstrap`.
///
/// > Important: The drain and ticker tasks keep the batcher alive, so a batcher
/// > is never reclaimed implicitly. Call ``shutdown()`` when the application
/// > stops; it drains the buffer, uploads what is left, and ends both tasks.
///
/// ## Example
/// ```swift
/// let signer = try APIKeySigner(configFilePath: "~/.oci/config")
/// let batcher = try OCILogBatcher(
///   configuration: OCILogHandlerConfiguration(logId: "ocid1.log.oc1.phx.EXAMPLE"),
///   region: .phx,
///   signer: signer
/// )
///
/// LoggingSystem.bootstrap { label in
///   OCILogHandler(label: label, batcher: batcher)
/// }
///
/// // ... later, on shutdown:
/// await batcher.shutdown()
/// ```
public actor OCILogBatcher {

  // MARK: - Immutable state (readable from any context)

  /// The configuration this batcher was built with.
  public let configuration: OCILogHandlerConfiguration

  /// The write end of the hand-off stream. ``OCILogHandler`` yields into it from
  /// its synchronous `log(...)` path.
  private let continuation: AsyncStream<OCILogRecord>.Continuation

  /// Counters shared with the handler. Guarded by a `Mutex` rather than actor
  /// isolation because the handler updates them from a synchronous context.
  private let counters = Mutex(OCILogHandlerStatistics())

  /// The client used for every flush.
  ///
  /// Its logger deliberately bypasses the bootstrapped `LoggingSystem` — see
  /// ``internalLogger``.
  private let client: LoggingIngestClient

  // MARK: - Isolated state

  /// Entries waiting to be flushed, already split to the configured entry length.
  private var buffer: [LogEntry] = []

  /// The UTF-8 size of ``buffer``, compared against
  /// ``OCILogHandlerConfiguration/flushSizeThreshold``.
  private var bufferedByteCount = 0

  /// The flush currently in progress, if any. Used to coalesce concurrent flushes.
  private var inFlightFlush: Task<Void, Never>?

  /// Whether ``shutdown()`` has already run.
  private var isShutDown = false

  /// The batcher's two long-lived tasks: the single consumer of the hand-off
  /// stream, and the interval-flush ticker.
  private struct LongLivedTasks: Sendable {
    /// The single consumer of the hand-off stream.
    var drain: Task<Void, Never>?
    /// The interval-flush ticker.
    var ticker: Task<Void, Never>?
  }

  /// The long-lived tasks, held outside actor isolation.
  ///
  /// Starting them means letting `self` escape from a non-isolated initializer,
  /// after which isolated properties are no longer assignable — so, like
  /// ``counters``, they live behind a `Mutex` instead.
  private let tasks = Mutex(LongLivedTasks())

  // MARK: - Initialization

  /// Creates a batcher and starts its drain and ticker tasks.
  ///
  /// - Parameters:
  ///   - configuration: Log OCID, batch identity, and flush/buffer tuning.
  ///   - region: A region used to determine the service endpoint.
  ///   - endpoint: The fully qualified endpoint URL. If provided, this takes precedence over the region.
  ///   - signer: A signer implementation used for authenticating requests.
  ///   - httpClient: The HTTP transport used to perform requests. Defaults to
  ///     ``HTTPClient/live`` (real `URLSession` I/O); tests can inject a recording transport.
  ///
  /// - Throws: ``LoggingIngestionError/missingRequiredParameter(_:)`` if neither endpoint nor region is specified.
  ///
  /// - Note: Either a region or an endpoint must be specified.
  ///   If an endpoint is specified, it will be used instead of the region.
  public init(
    configuration: OCILogHandlerConfiguration,
    region: Region? = nil,
    endpoint: String? = nil,
    signer: Signer,
    httpClient: HTTPClient = .live
  ) throws {
    self.configuration = configuration
    self.client = try LoggingIngestClient(
      region: region,
      endpoint: endpoint,
      signer: signer,
      retryConfig: configuration.retryConfig,
      logger: Self.internalLogger,
      httpClient: httpClient
    )

    let (stream, continuation) = AsyncStream.makeStream(
      of: OCILogRecord.self,
      // `max(1,)` guards a capacity mutated onto the configuration after `init` clamped it.
      bufferingPolicy: .bufferingOldest(max(1, configuration.bufferCapacity))
    )
    self.continuation = continuation

    let drainTask = Task { [self] in await drain(stream) }
    let tickerTask = Task { [self] in await runTicker() }
    tasks.withLock { $0 = LongLivedTasks(drain: drainTask, ticker: tickerTask) }
  }

  /// The logger handed to the batcher's internal ``LoggingIngestClient``.
  ///
  /// This is the recursion guard. The client — and
  /// ``HTTPClient/send(_:signer:retry:logger:)`` underneath it — emits debug
  /// records while flushing; routing them through the bootstrapped
  /// `LoggingSystem` would make every flush produce more records to flush. A
  /// private no-op backend keeps that traffic out of the bootstrapped system
  /// entirely, regardless of what the application bootstrapped.
  ///
  /// The SDK's global ``logger`` (label `"OCIKit"`), which the request signer
  /// writes to, *is* bootstrapped and cannot be redirected here; it is handled by
  /// ``OCILogHandlerConfiguration/excludedLoggerLabels`` instead.
  private static let internalLogger = Logger(label: "OCILogBatcher") { _ in SwiftLogNoOpLogHandler() }

  // MARK: - Hand-off (callable from any context)

  /// Hands a rendered record to the batcher without blocking.
  ///
  /// This is the synchronous seam ``OCILogHandler`` uses. When the hand-off
  /// buffer is full the record is discarded — the buffer keeps the oldest
  /// records — and ``OCILogHandlerStatistics/dropped`` is incremented.
  ///
  /// - Parameter record: The rendered record to ship.
  public nonisolated func enqueue(_ record: OCILogRecord) {
    let result = continuation.yield(record)
    counters.withLock { stats in
      if case .enqueued = result {
        stats.enqueued &+= 1
      }
      else {
        stats.dropped &+= 1
      }
    }
  }

  /// A snapshot of what this batcher has enqueued, dropped, submitted, and failed.
  public nonisolated var statistics: OCILogHandlerStatistics {
    counters.withLock { $0 }
  }

  /// Whether records from `label` are dropped rather than shipped, per
  /// ``OCILogHandlerConfiguration/excludedLoggerLabels``.
  ///
  /// - Parameter label: The swift-log logger label to test.
  /// - Returns: `true` when records carrying this label must not be shipped.
  public nonisolated func isExcluded(loggerLabel label: String) -> Bool {
    configuration.excludedLoggerLabels.contains(label)
  }

  // MARK: - Flushing

  /// Uploads everything currently buffered and returns once the upload has
  /// finished (successfully or not).
  ///
  /// Concurrent calls are coalesced: a caller that arrives while an upload is in
  /// flight waits for it before taking its own turn, so at most one `PutLogs`
  /// request is ever outstanding.
  public func flush() async {
    // Coalesce with an upload already in progress.
    if let existing = inFlightFlush {
      await existing.value
      // Whoever created the task clears it; clear it here too in case this caller
      // resumed first, so the records below are not stranded behind a finished task.
      if inFlightFlush == existing { inFlightFlush = nil }
    }

    guard !buffer.isEmpty else { return }

    let entries = buffer
    let flushTime = Date()
    buffer.removeAll(keepingCapacity: true)
    bufferedByteCount = 0

    let task = Task { [self] in await submit(entries, at: flushTime) }
    inFlightFlush = task
    await task.value
    if inFlightFlush == task { inFlightFlush = nil }
  }

  /// Stops accepting records, drains the buffer, and ends the drain and ticker tasks.
  ///
  /// Idempotent. After it returns, ``enqueue(_:)`` discards records and counts
  /// them in ``OCILogHandlerStatistics/dropped``.
  public func shutdown() async {
    guard !isShutDown else { return }
    isShutDown = true

    let running = tasks.withLock { current -> LongLivedTasks in
      let snapshot = current
      current = LongLivedTasks()
      return snapshot
    }
    running.ticker?.cancel()

    // Ends the `for await` in `drain(_:)` once the already-buffered records have
    // been consumed; `drain` performs the final flush before it returns.
    continuation.finish()
    await running.drain?.value

    // The drain task's terminal flush may have coalesced with an in-flight one;
    // make sure nothing is left behind.
    await flush()
  }

  // MARK: - Internals

  /// The stream's single consumer: accumulate, flush on the size threshold, and
  /// flush once more when the stream ends.
  private func drain(_ stream: AsyncStream<OCILogRecord>) async {
    for await record in stream {
      append(record)
      if bufferedByteCount >= configuration.flushSizeThreshold {
        await flush()
      }
    }
    await flush()
  }

  /// Flushes on a fixed interval until cancelled. The `Task.sleep` is
  /// cancellation-cooperative, so ``shutdown()`` ends this loop promptly.
  private func runTicker() async {
    // A non-positive interval disables interval flushing; only the size
    // threshold and explicit flushes remain.
    guard configuration.flushInterval > 0 else { return }

    while !Task.isCancelled {
      do {
        try await Task.sleep(for: .seconds(configuration.flushInterval))
      }
      catch {
        return  // cancelled
      }
      await flush()
    }
  }

  /// Turns one record into one or more entries and appends them to the buffer.
  private func append(_ record: OCILogRecord) {
    for chunk in Self.split(record.data, maxLength: configuration.maxEntryLength) {
      buffer.append(LogEntry(data: chunk, time: record.time))
      bufferedByteCount += chunk.utf8.count
    }
  }

  /// Performs one `PutLogs` call and records its outcome in the counters.
  private func submit(_ entries: [LogEntry], at flushTime: Date) async {
    let details = PutLogsDetails(
      logEntryBatches: [
        LogEntryBatch(
          entries: entries,
          source: configuration.source,
          type: configuration.type,
          subject: configuration.subject,
          defaultlogentrytime: flushTime
        )
      ]
    )

    do {
      try await client.putLogs(logId: configuration.logId, details: details)
      counters.withLock { $0.submitted &+= UInt64(entries.count) }
    }
    catch {
      // Deliberately not logged: writing a failure through the bootstrapped
      // `LoggingSystem` is exactly the recursion this backend guards against.
      counters.withLock { stats in
        stats.failed &+= UInt64(entries.count)
        stats.flushFailures &+= 1
        stats.lastFlushErrorDescription = String(describing: error)
      }
    }
  }

  /// Splits `data` into consecutive chunks of at most `maxLength` characters.
  ///
  /// The service silently truncates any entry longer than 10,000 characters to
  /// exactly 10,000 characters ending in `...`, so long messages are split
  /// client-side instead. Order is preserved, so the parts read contiguously.
  ///
  /// - Parameters:
  ///   - data: The rendered log line.
  ///   - maxLength: The maximum number of characters per chunk.
  /// - Returns: `[data]` when it already fits, otherwise its consecutive chunks.
  static func split(_ data: String, maxLength: Int) -> [String] {
    guard maxLength > 0, data.count > maxLength else { return [data] }

    var chunks: [String] = []
    var start = data.startIndex
    while start < data.endIndex {
      let end = data.index(start, offsetBy: maxLength, limitedBy: data.endIndex) ?? data.endIndex
      chunks.append(String(data[start..<end]))
      start = end
    }
    return chunks
  }
}
