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

/// A point-in-time snapshot of what an ``OCILogBatcher`` has done so far.
///
/// A log backend cannot report its own failures through the logging system it
/// implements, so it reports them here instead. Read a snapshot from
/// ``OCILogBatcher/statistics`` or ``OCILogHandler/statistics`` — e.g. to expose
/// it as a metric, or to assert on it in a test.
///
/// ## Example
/// ```swift
/// let stats = batcher.statistics
/// if stats.dropped > 0 {
///   // The hand-off buffer is too small for this workload, or flushes are failing.
/// }
/// ```
public struct OCILogHandlerStatistics: Sendable, Equatable {
  /// Records accepted into the hand-off buffer.
  public internal(set) var enqueued: UInt64 = 0

  /// Records discarded without ever reaching the batcher, because the hand-off
  /// buffer was full or the batcher had already shut down.
  ///
  /// The buffer keeps the oldest records, so a drop always discards the *newest*
  /// record. A non-zero value means
  /// ``OCILogHandlerConfiguration/bufferCapacity`` is too small for the burst
  /// rate, or flushes are failing/stalling.
  public internal(set) var dropped: UInt64 = 0

  /// Log entries the service accepted. One record can become several entries
  /// when its message is split, so this counts entries rather than records.
  public internal(set) var submitted: UInt64 = 0

  /// Log entries lost because their flush failed. Failed flushes are not
  /// re-buffered: retrying inside the flush is
  /// ``OCILogHandlerConfiguration/retryConfig``'s job.
  public internal(set) var failed: UInt64 = 0

  /// How many flushes ended in an error.
  public internal(set) var flushFailures: UInt64 = 0

  /// A description of the most recent flush failure, or `nil` if none has occurred.
  ///
  /// This is the only place a flush failure surfaces: the batcher never writes
  /// to the bootstrapped `LoggingSystem`, since that is the recursion
  /// ``OCILogHandler`` exists to avoid.
  public internal(set) var lastFlushErrorDescription: String?

  /// Creates an all-zero snapshot.
  init() {}
}
