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

/// One already-rendered log record on its way from ``OCILogHandler`` to
/// ``OCILogBatcher``.
///
/// The handler formats a swift-log record into ``data`` on the caller's thread —
/// that is the only work the synchronous `log(...)` hot path does besides a
/// non-blocking hand-off. Everything downstream (UUID generation, splitting long
/// messages, batching, uploading) happens on the batcher, off the hot path.
public struct OCILogRecord: Sendable, Equatable {
  /// The rendered log line. Values longer than
  /// ``OCILogHandlerConfiguration/maxEntryLength`` are split across consecutive
  /// ``LogEntry`` values by the batcher.
  public let data: String

  /// When the record was logged. Becomes the entry's ``LogEntry/time``, so the
  /// timestamp reflects when the application logged, not when the batch flushed.
  public let time: Date

  /// Creates a record.
  ///
  /// - Parameters:
  ///   - data: The rendered log line.
  ///   - time: When the record was logged. Defaults to now.
  public init(data: String, time: Date = Date()) {
    self.data = data
    self.time = time
  }
}
