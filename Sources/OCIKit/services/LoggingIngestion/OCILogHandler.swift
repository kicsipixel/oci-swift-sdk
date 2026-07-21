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
import Logging

/// A swift-log backend that ships records to OCI Logging.
///
/// Bootstrap it once at start-up and the rest of the application keeps using
/// plain `Logger` values; every record is rendered, handed to an
/// ``OCILogBatcher``, and uploaded in batches with `PutLogs`.
///
/// The synchronous `log(...)` path does exactly two things: render the record
/// and hand it off. It never blocks, never performs I/O, and never spawns a
/// task — see ``OCILogBatcher`` for why. When the hand-off buffer is full the
/// newest record is dropped and counted in
/// ``OCILogHandlerStatistics/dropped``; nothing upstream ever stalls on logging.
///
/// ## Bootstrap
/// ```swift
/// import Logging
/// import OCIKit
///
/// let signer = try APIKeySigner(configFilePath: "~/.oci/config")
/// let batcher = try OCILogBatcher(
///   configuration: OCILogHandlerConfiguration(
///     logId: "ocid1.log.oc1.phx.EXAMPLE",
///     type: "com.example.orders"
///   ),
///   region: .phx,
///   signer: signer
/// )
///
/// // Keep console output as well as shipping to OCI.
/// LoggingSystem.bootstrap { label in
///   MultiplexLogHandler([
///     StreamLogHandler.standardOutput(label: label),
///     OCILogHandler(label: label, batcher: batcher, logLevel: .info),
///   ])
/// }
///
/// let log = Logger(label: "com.example.orders")
/// log.info("order placed", metadata: ["orderId": "1234"])
///
/// // Before the process exits, so buffered records are not lost:
/// await batcher.shutdown()
/// ```
///
/// > Note: An SDK never bootstraps a process-global system on the
/// > application's behalf, so `LoggingSystem.bootstrap` stays the caller's call.
public struct OCILogHandler: LogHandler {
  /// The swift-log label of the logger this handler backs.
  public let label: String

  /// The batcher this handler hands records to. Shared by every handler created
  /// from the same bootstrap closure.
  public let batcher: OCILogBatcher

  /// The minimum level this handler emits.
  public var logLevel: Logger.Level

  /// Metadata attached to every record this handler emits.
  public var metadata: Logger.Metadata

  /// The metadata provider consulted on every record, if any.
  public var metadataProvider: Logger.MetadataProvider?

  /// Whether ``label`` is on the batcher's exclusion list. Resolved once, because
  /// swift-log creates one handler per label.
  private let isExcluded: Bool

  /// Creates a handler for one logger label.
  ///
  /// - Parameters:
  ///   - label: The swift-log label, as handed to the `LoggingSystem.bootstrap` closure.
  ///   - batcher: The batcher that buffers and uploads records.
  ///   - logLevel: The minimum level to emit. Defaults to `.info`.
  ///   - metadata: Metadata attached to every record. Defaults to empty.
  ///   - metadataProvider: A provider consulted on every record. Defaults to `nil`.
  public init(
    label: String,
    batcher: OCILogBatcher,
    logLevel: Logger.Level = .info,
    metadata: Logger.Metadata = [:],
    metadataProvider: Logger.MetadataProvider? = nil
  ) {
    self.label = label
    self.batcher = batcher
    self.logLevel = logLevel
    self.metadata = metadata
    self.metadataProvider = metadataProvider
    self.isExcluded = batcher.isExcluded(loggerLabel: label)
  }

  /// A snapshot of the shared batcher's counters — enqueued, dropped, submitted,
  /// failed. Flush failures surface here and nowhere else.
  public var statistics: OCILogHandlerStatistics { batcher.statistics }

  public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
    get { metadata[key] }
    set { metadata[key] = newValue }
  }

  /// Renders one record and hands it to the batcher.
  ///
  /// `Logger` has already checked ``logLevel`` by the time this is called.
  ///
  /// > Note: This is swift-log's classic flat-parameter entry point rather than
  /// > the `log(event:)` one introduced in swift-log 1.14, so the handler works
  /// > across the whole 1.x line and the package keeps its `from: "1.0.0"` floor.
  /// > Building against 1.14 therefore reports the `log(event:)` default
  /// > implementation as deprecated; raising the floor and adopting `LogEvent` is
  /// > tracked separately.
  public func log(
    level: Logger.Level,
    message: Logger.Message,
    metadata explicitMetadata: Logger.Metadata?,
    source: String,
    file: String,
    function: String,
    line: UInt
  ) {
    // Recursion guard: records the SDK itself emits through the bootstrapped
    // system must not become records to ship, or every flush would feed the next.
    guard !isExcluded else { return }

    let now = Date()
    let rendered = Self.render(
      timestamp: now,
      level: level,
      label: label,
      message: message,
      metadata: effectiveMetadata(explicitMetadata),
      source: source
    )
    batcher.enqueue(OCILogRecord(data: rendered, time: now))
  }

  // MARK: - Rendering

  /// Merges handler metadata, provider metadata, and the record's own metadata,
  /// in increasing order of precedence. Returns `nil` when there is none.
  private func effectiveMetadata(_ explicitMetadata: Logger.Metadata?) -> Logger.Metadata? {
    var merged = metadata
    let provided = metadataProvider?.get() ?? [:]

    guard !merged.isEmpty || !provided.isEmpty || !(explicitMetadata?.isEmpty ?? true) else {
      return nil
    }
    if !provided.isEmpty {
      merged.merge(provided) { _, provided in provided }
    }
    if let explicitMetadata, !explicitMetadata.isEmpty {
      merged.merge(explicitMetadata) { _, explicit in explicit }
    }
    return merged
  }

  /// Renders a record into the text stored in ``LogEntry/data``.
  ///
  /// The layout mirrors swift-log's own `StreamLogHandler` so a log read in the
  /// OCI Console looks like the same record read on the console, except that the
  /// timestamp is RFC3339 (matching ``LogEntry/time``) and there is no trailing
  /// newline:
  ///
  /// ```
  /// 2026-07-21T15:49:00.123Z info com.example.orders : orderId=1234 [Orders] order placed
  /// ```
  ///
  /// - Parameters:
  ///   - timestamp: When the record was logged.
  ///   - level: The record's level.
  ///   - label: The logger label.
  ///   - message: The logged message.
  ///   - metadata: The already-merged metadata, or `nil` when there is none.
  ///   - source: The swift-log source (by default the emitting module).
  /// - Returns: The rendered line.
  static func render(
    timestamp: Date,
    level: Logger.Level,
    label: String,
    message: Logger.Message,
    metadata: Logger.Metadata?,
    source: String
  ) -> String {
    let renderedMetadata = metadata.flatMap { $0.isEmpty ? nil : prettify($0) }
    return
      "\(timestamp.toRFC3339()) \(level) \(label) :\(renderedMetadata.map { " \($0)" } ?? "") [\(source)] \(message)"
  }

  /// Renders metadata as `key=value` pairs, sorted by key so a record's text is
  /// stable across runs.
  static func prettify(_ metadata: Logger.Metadata) -> String {
    metadata
      .sorted { $0.key < $1.key }
      .map { "\($0)=\($1)" }
      .joined(separator: " ")
  }
}
