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
import Synchronization

/// The process-wide set of live metric handlers, keyed by ``OCIMetricsStreamID``.
///
/// The registry is the boundary between the two halves of the backend:
///
/// - ``OCIMetricsFactory`` calls ``counter(id:)`` / ``recorder(id:aggregate:)`` / ``timer(id:)`` on
///   the *application's* thread whenever a metric is created. Creation is get-or-create under a
///   single `Mutex` (`Synchronization`), so two modules that declare the same
///   `Counter("requests", ["host": "a"])` share one handler and aggregate into one stream.
/// - ``OCIMetricsExporter`` calls ``drain()`` once per step, which takes every handler's
///   accumulated values away without unregistering anything.
///
/// Nothing here is `async`: the lock is only ever held for dictionary work and never across an
/// `await`, which is what lets the recording hot path stay synchronous and non-blocking.
final class OCIMetricsRegistry: Sendable {
  /// The buffer bounds and per-step sample bound applied to the handlers this registry creates.
  private let configuration: OCIMetricsConfiguration

  /// All registry state, guarded by ``state``.
  private struct State {
    /// The live handlers.
    var handlers: [OCIMetricsStreamID: any OCIMetricsDrainable] = [:]
    /// Final samples taken from handlers that were destroyed between two exports, held until the
    /// next drain so a destroyed instrument's last step is still published.
    var orphans: [OCIMetricsStreamSnapshot] = []
    /// Observations dropped by handlers that hit their per-step sample bound.
    var droppedSamples: Int = 0
  }

  private let state = Mutex(State())

  /// Creates an empty registry.
  ///
  /// - Parameter configuration: Supplies ``OCIMetricsConfiguration/maximumSamplesPerStream`` for
  ///   the handlers created here, and ``OCIMetricsConfiguration/maximumBufferedStreams`` as the
  ///   bound on retained snapshots of destroyed handlers.
  init(configuration: OCIMetricsConfiguration) {
    self.configuration = configuration
  }

  // MARK: - Handler lookup

  /// Returns the counter handler for `id`, creating and registering it on first use.
  ///
  /// - Parameter id: The stream identity, whose ``OCIMetricsStreamID/kind`` must be
  ///   ``OCIMetricsStreamID/Kind/counter``.
  /// - Returns: The shared handler for that stream.
  func counter(id: OCIMetricsStreamID) -> OCIMetricsCounterHandler {
    state.withLock { state in
      if let existing = state.handlers[id] as? OCIMetricsCounterHandler { return existing }
      let handler = OCIMetricsCounterHandler(id: id)
      state.handlers[id] = handler
      return handler
    }
  }

  /// Returns the recorder handler for `id`, creating and registering it on first use.
  ///
  /// - Parameters:
  ///   - id: The stream identity, whose ``OCIMetricsStreamID/kind`` must be
  ///     ``OCIMetricsStreamID/Kind/recorder`` or ``OCIMetricsStreamID/Kind/gauge``.
  ///   - aggregate: `true` for a `Recorder`, `false` for a `Gauge`.
  /// - Returns: The shared handler for that stream.
  func recorder(id: OCIMetricsStreamID, aggregate: Bool) -> OCIMetricsRecorderHandler {
    state.withLock { state in
      if let existing = state.handlers[id] as? OCIMetricsRecorderHandler { return existing }
      let handler = OCIMetricsRecorderHandler(
        id: id,
        aggregate: aggregate,
        maximumSamples: configuration.maximumSamplesPerStream
      )
      state.handlers[id] = handler
      return handler
    }
  }

  /// Returns the timer handler for `id`, creating and registering it on first use.
  ///
  /// - Parameter id: The stream identity, whose ``OCIMetricsStreamID/kind`` must be
  ///   ``OCIMetricsStreamID/Kind/timer``.
  /// - Returns: The shared handler for that stream.
  func timer(id: OCIMetricsStreamID) -> OCIMetricsTimerHandler {
    state.withLock { state in
      if let existing = state.handlers[id] as? OCIMetricsTimerHandler { return existing }
      let handler = OCIMetricsTimerHandler(id: id, maximumSamples: configuration.maximumSamplesPerStream)
      state.handlers[id] = handler
      return handler
    }
  }

  // MARK: - Destruction

  /// Unregisters `handler` and retains its final samples for the next export.
  ///
  /// swift-metrics calls `destroy()` when an instrument goes out of scope, which may well happen
  /// mid-step. Draining the handler here means the values recorded since the last export are
  /// published rather than discarded; the retained snapshots are bounded by
  /// ``OCIMetricsConfiguration/maximumBufferedStreams`` and the oldest are dropped on overflow.
  ///
  /// - Parameter handler: The handler swift-metrics is destroying. A handler that is not the one
  ///   currently registered for its id — which happens when an instrument is destroyed twice — is
  ///   drained but leaves the registry untouched.
  func destroy(_ handler: some OCIMetricsDrainable) {
    let residual = handler.drain()
    state.withLock { state in
      if state.handlers[handler.id] === handler {
        state.handlers.removeValue(forKey: handler.id)
      }
      guard !residual.isEmpty else { return }
      state.orphans.append(OCIMetricsStreamSnapshot(id: handler.id, samples: residual))
      if state.orphans.count > configuration.maximumBufferedStreams {
        state.orphans.removeFirst(state.orphans.count - configuration.maximumBufferedStreams)
      }
    }
  }

  // MARK: - Draining

  /// Takes one step's values from every live handler, plus anything left behind by handlers
  /// destroyed since the previous drain.
  ///
  /// Handlers with nothing to report are skipped, so an idle process posts nothing at all.
  ///
  /// - Returns: The step's snapshots, ordered by ``OCIMetricsStreamID/sortKey`` so the composition
  ///   of each ≤50-stream request is deterministic, together with the number of observations the
  ///   handlers had to drop to stay within their per-step sample bound.
  func drain() -> (snapshots: [OCIMetricsStreamSnapshot], droppedSamples: Int) {
    let (handlers, orphans) = state.withLock { state in
      let handlers = Array(state.handlers.values)
      let orphans = state.orphans
      state.orphans.removeAll(keepingCapacity: true)
      return (handlers, orphans)
    }

    var snapshots = orphans
    var droppedSamples = 0
    snapshots.reserveCapacity(orphans.count + handlers.count)
    for handler in handlers {
      let samples = handler.drain()
      droppedSamples += handler.takeDroppedSamples()
      guard !samples.isEmpty else { continue }
      snapshots.append(OCIMetricsStreamSnapshot(id: handler.id, samples: samples))
    }
    snapshots.sort { $0.id.sortKey < $1.id.sortKey }
    return (snapshots, droppedSamples)
  }
}
