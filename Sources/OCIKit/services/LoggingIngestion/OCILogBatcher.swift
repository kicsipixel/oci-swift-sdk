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
// ## Why the stream carries barriers as well as records
//
// The buffer a flush uploads is filled by the drain task, not by `enqueue(_:)` —
// a record yielded a moment ago may still be sitting in the stream when a caller
// asks to flush. `flush()` therefore yields a barrier of its own and waits for
// the drain task to reach it: the stream is FIFO, so once the barrier has been
// consumed every record yielded before it is provably in the buffer.
//

import Foundation
import Logging
import Synchronization

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

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
/// ## What happens when a flush fails
///
/// A failed batch is put back at the head of the buffer and retried by a later
/// flush, so records survive a transient outage — the service accepts entries as
/// old as the log's retention window. The retained buffer is bounded by
/// ``OCILogHandlerConfiguration/bufferCapacity`` entries: past that the *oldest*
/// entries are dropped and counted in ``OCILogHandlerStatistics/failed``, so the
/// drop policy is capacity-driven rather than staleness-driven. The one
/// exception is a flush that fails during ``shutdown()``, where nothing is left
/// to retry it — those entries are lost and counted as failed.
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

  // MARK: - Recursion guard

  /// Whether the current task is somewhere inside a flush.
  ///
  /// This is the recursion guard that does not depend on knowing every logger
  /// label. ``submit(_:at:)`` binds it around the `PutLogs` call, and a
  /// task-local is inherited by the entire async call tree that call drives — a
  /// custom ``HTTPClient`` transport, a custom ``Signer``, retry logic, any
  /// third-party code on the request path. ``OCILogHandler/log(level:message:metadata:source:file:function:line:)``
  /// and ``enqueue(_:)`` drop records while it is set, so a log emitted from
  /// inside a flush can never become another record to flush.
  ///
  /// It is process-wide rather than per-batcher: while one batcher is uploading,
  /// records produced on that task are dropped by every batcher. That is
  /// deliberate — the alternative is an amplification loop between two batchers.
  @TaskLocal
  static var isFlushing = false

  // MARK: - Immutable state (readable from any context)

  /// The configuration this batcher was built with.
  public let configuration: OCILogHandlerConfiguration

  /// The write end of the hand-off stream. ``OCILogHandler`` yields into it from
  /// its synchronous `log(...)` path.
  private let continuation: AsyncStream<HandOff>.Continuation

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

  /// The id handed to the next barrier yielded by ``flush()``.
  private var nextBarrierID: UInt64 = 0

  /// Callers of ``flush()`` waiting for their barrier to reach the drain task.
  private var barrierWaiters: [UInt64: CheckedContinuation<Void, Never>] = [:]

  /// Barriers the drain task consumed before their waiter had registered.
  private var deliveredBarriers: Set<UInt64> = []

  /// One item on the hand-off stream.
  private enum HandOff: Sendable {
    /// A rendered record on its way to the buffer.
    case record(OCILogRecord)
    /// A marker ``flush()`` waits on to know the records before it are buffered.
    case barrier(id: UInt64)
  }

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
      httpClient: Self.bounding(httpClient, to: configuration.requestTimeout)
    )

    let (stream, continuation) = AsyncStream.makeStream(
      of: HandOff.self,
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
  /// This is the first half of the recursion guard. The client — and
  /// ``HTTPClient/send(_:signer:retry:logger:)`` underneath it — emits debug
  /// records while flushing; routing them through the bootstrapped
  /// `LoggingSystem` would make every flush produce more records to flush. A
  /// private no-op backend keeps that traffic out of the bootstrapped system
  /// entirely, regardless of what the application bootstrapped.
  ///
  /// Code the batcher does not own — a custom transport, a custom signer, the
  /// SDK's own global ``logger`` (label `"OCIKit"`) — writes to the bootstrapped
  /// system instead; ``isFlushing`` and
  /// ``OCILogHandlerConfiguration/excludedLoggerLabels`` cover those.
  private static let internalLogger = Logger(label: "OCILogBatcher") { _ in SwiftLogNoOpLogHandler() }

  /// Wraps `client` so every flush request carries a bounded `timeoutInterval`.
  ///
  /// Without it each attempt inherits `URLSession`'s 60-second default, and a
  /// timeout is retryable — so an unreachable endpoint could hold ``shutdown()``
  /// for minutes. Cancellation is not a usable bound here: the Linux
  /// `URLSession` async shim does not cancel its underlying task.
  ///
  /// - Parameters:
  ///   - client: The transport to wrap.
  ///   - timeout: Seconds allowed per attempt; non-positive leaves `client` untouched.
  /// - Returns: A transport that stamps `timeoutInterval` onto every request.
  private static func bounding(_ client: HTTPClient, to timeout: TimeInterval) -> HTTPClient {
    guard timeout > 0 else { return client }
    return HTTPClient { request in
      var request = request
      request.timeoutInterval = timeout
      return try await client.data(request)
    }
  }

  // MARK: - Hand-off (callable from any context)

  /// Hands a rendered record to the batcher without blocking.
  ///
  /// This is the synchronous seam ``OCILogHandler`` uses. When the hand-off
  /// buffer is full the record is discarded — the buffer keeps the oldest
  /// records — and ``OCILogHandlerStatistics/dropped`` is incremented.
  ///
  /// Records offered from inside a flush (see ``isFlushing``) are discarded
  /// without being counted: shipping them is the recursion this backend exists
  /// to avoid.
  ///
  /// - Parameter record: The rendered record to ship.
  public nonisolated func enqueue(_ record: OCILogRecord) {
    guard !Self.isFlushing else { return }

    let result = continuation.yield(.record(record))
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
  /// The mandatory labels in
  /// ``OCILogHandlerConfiguration/defaultExcludedLoggerLabels`` are always
  /// excluded, even if they were removed from a configuration after it was
  /// created.
  ///
  /// - Parameter label: The swift-log logger label to test.
  /// - Returns: `true` when records carrying this label must not be shipped.
  public nonisolated func isExcluded(loggerLabel label: String) -> Bool {
    configuration.excludedLoggerLabels.contains(label)
      || OCILogHandlerConfiguration.defaultExcludedLoggerLabels.contains(label)
  }

  // MARK: - Flushing

  /// Uploads everything logged before this call and returns once the upload has
  /// finished (successfully or not).
  ///
  /// Records still in transit between ``enqueue(_:)`` and the buffer are waited
  /// for first, so a flush issued right before the process exits ships them too.
  ///
  /// Concurrent calls are coalesced: a caller that arrives while an upload is in
  /// flight waits for it before taking its own turn, so at most one `PutLogs`
  /// request is ever outstanding.
  public func flush() async {
    await awaitHandOffDrain()
    await flushBuffered()
  }

  /// Stops accepting records, drains the buffer, and ends the drain and ticker tasks.
  ///
  /// Idempotent. After it returns, ``enqueue(_:)`` discards records and counts
  /// them in ``OCILogHandlerStatistics/dropped``.
  ///
  /// > Important: This waits for the final upload, so it is bounded by the flush
  /// > budget rather than being instantaneous: at worst
  /// > `retryConfig.maxAttempts × requestTimeout + retryConfig.maxCumulativeDelay`
  /// > (40 seconds with the defaults). Shorten
  /// > ``OCILogHandlerConfiguration/requestTimeout`` or
  /// > ``OCILogHandlerConfiguration/retryConfig`` if the process has a tighter
  /// > termination grace period. A batch whose final flush fails is lost —
  /// > nothing is left to retry it — and counted in
  /// > ``OCILogHandlerStatistics/failed``.
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
    await flushBuffered()
  }

  // MARK: - Internals

  /// Waits until every record yielded before this call has reached ``buffer``.
  ///
  /// Only ``flush()`` uses this. The drain task must never call it: it is the
  /// consumer that resolves the barrier, so waiting on its own barrier would
  /// deadlock.
  private func awaitHandOffDrain() async {
    let id = nextBarrierID
    nextBarrierID &+= 1

    // A barrier that never entered the stream (the hand-off buffer was full, or
    // the stream has already finished) will never come back out of it.
    guard case .enqueued = continuation.yield(.barrier(id: id)) else { return }

    await withCheckedContinuation { (waiter: CheckedContinuation<Void, Never>) in
      if deliveredBarriers.remove(id) != nil {
        waiter.resume()
      }
      else {
        barrierWaiters[id] = waiter
      }
    }
  }

  /// Releases the ``flush()`` call waiting on `id`, if it has registered yet.
  private func releaseBarrier(id: UInt64) {
    if let waiter = barrierWaiters.removeValue(forKey: id) {
      waiter.resume()
    }
    else {
      deliveredBarriers.insert(id)
    }
  }

  /// Uploads the current ``buffer``, coalescing with any upload already running.
  ///
  /// This is ``flush()`` without the hand-off barrier, for callers that are the
  /// drain task itself or that have already ended the stream.
  private func flushBuffered() async {
    // Coalesce with uploads already in progress. This loops rather than testing
    // once: a caller that waited may find that a *different* caller installed a
    // new flush while it was suspended, and overwriting that still-running task
    // would put two `PutLogs` on the wire and orphan the first one.
    while let existing = inFlightFlush {
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

  /// The stream's single consumer: accumulate, flush on the size threshold, and
  /// flush once more when the stream ends.
  private func drain(_ stream: AsyncStream<HandOff>) async {
    for await element in stream {
      switch element {
      case .record(let record):
        append(record)
        if bufferedByteCount >= configuration.flushSizeThreshold {
          await flushBuffered()
        }
      case .barrier(let id):
        releaseBarrier(id: id)
      }
    }

    // The stream is done, so any barrier still outstanding will never arrive.
    // `deliveredBarriers` is deliberately left alone: it is what a waiter that
    // has not registered yet looks in, and dropping its id would strand it.
    for waiter in barrierWaiters.values { waiter.resume() }
    barrierWaiters.removeAll()

    await flushBuffered()
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
      await flushBuffered()
    }
  }

  /// Turns one record into one or more entries and appends them to the buffer.
  private func append(_ record: OCILogRecord) {
    // Clamped here, not just in the configuration's initializer: the property is
    // publicly mutable, and an over-long entry is silently truncated server-side.
    let maxLength = min(
      OCILogHandlerConfiguration.serviceEntryLengthLimit,
      max(1, configuration.maxEntryLength)
    )
    for chunk in Self.split(record.data, maxLength: maxLength) {
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
      // Everything this call reaches — the transport, the signer, retry logic —
      // runs with `isFlushing` bound, so whatever it logs is dropped instead of
      // becoming the next batch to upload.
      try await Self.$isFlushing.withValue(true) {
        try await client.putLogs(logId: configuration.logId, details: details)
      }
      counters.withLock { $0.submitted &+= UInt64(entries.count) }
    }
    catch {
      // Deliberately not logged: writing a failure through the bootstrapped
      // `LoggingSystem` is exactly the recursion this backend guards against.
      counters.withLock { stats in
        stats.flushFailures &+= 1
        stats.lastFlushErrorDescription = String(describing: error)
      }
      requeue(entries)
    }
  }

  /// Puts a failed batch back at the head of the buffer so a later flush retries it.
  ///
  /// Buffered entries do not go stale — the service accepts entries as old as the
  /// log's retention window — so the only reason to give up on them is capacity:
  /// once the buffer exceeds ``OCILogHandlerConfiguration/bufferCapacity`` the
  /// oldest entries are dropped and counted in
  /// ``OCILogHandlerStatistics/failed``. After ``shutdown()`` there is nothing
  /// left to retry, so the whole batch is counted as failed instead.
  private func requeue(_ entries: [LogEntry]) {
    guard !isShutDown else {
      counters.withLock { $0.failed &+= UInt64(entries.count) }
      return
    }

    buffer.insert(contentsOf: entries, at: 0)
    bufferedByteCount += entries.reduce(0) { $0 + $1.data.utf8.count }

    let capacity = max(1, configuration.bufferCapacity)
    guard buffer.count > capacity else { return }

    let overflow = buffer.count - capacity
    bufferedByteCount -= buffer.prefix(overflow).reduce(0) { $0 + $1.data.utf8.count }
    buffer.removeFirst(overflow)
    counters.withLock { $0.failed &+= UInt64(overflow) }
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
