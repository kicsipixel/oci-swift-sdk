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

/// A batch of log entries that share a single source, type, and subject.
///
/// A ``PutLogsDetails`` payload carries one or more batches; group entries into
/// separate batches only when they differ in ``source``, ``type``, or ``subject``.
public struct LogEntryBatch: Codable, Sendable {
  /// The log entries in this batch.
  public let entries: [LogEntry]

  /// The source of the logs that generated the messages. This is typically the
  /// instance name, the hostname, or the source used to read the event —
  /// for example `"ServerA"`.
  public let source: String

  /// The type of the logs being ingested — for example `"ServerA.requestLogs"`.
  public let type: String

  /// The specific sub-resource or input file the events were read from —
  /// for example `"/var/log/application.log"`. Optional.
  public let subject: String?

  /// The default timestamp for every entry in this batch, RFC3339-formatted with
  /// milliseconds precision. An entry's own ``LogEntry/time`` overrides it.
  ///
  /// > Note: The service applies no clock-skew rejection. Entries as old as the
  /// > log's retention window are accepted and indexed at their claimed time
  /// > (anything older returns HTTP 200 but is dropped), and future timestamps are
  /// > accepted. Logs buffered across an outage therefore stay ingestible for days.
  public let defaultlogentrytime: String

  /// Creates a batch of log entries.
  ///
  /// - Parameters:
  ///   - entries: The log entries to send.
  ///   - source: The source of the logs, e.g. the hostname or instance name.
  ///   - type: The type of the logs, e.g. `"ServerA.requestLogs"`.
  ///   - subject: The sub-resource or input file the events came from. Optional.
  ///   - defaultlogentrytime: The default timestamp for entries that carry no
  ///     ``LogEntry/time`` of their own, encoded as RFC3339 with milliseconds.
  public init(
    entries: [LogEntry],
    source: String,
    type: String,
    subject: String? = nil,
    defaultlogentrytime: Date
  ) {
    self.entries = entries
    self.source = source
    self.type = type
    self.subject = subject
    self.defaultlogentrytime = defaultlogentrytime.toRFC3339()
  }
}
