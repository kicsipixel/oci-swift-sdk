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
// Credential-free unit tests for issue #91 (OCIMetricsFactory), test group 3:
// Counter/Recorder/Gauge/Timer per-step aggregation semantics, exercised
// directly against the Mutex-guarded handlers — deterministic, no clock, no
// sleeping. No ~/.oci/config, no network.
//

import Foundation
import Testing

@testable import OCIKit

// MARK: - OCIMetricsCounterHandler

struct OCIMetricsCounterHandlerTests {
  private func makeHandler(label: String = "requests") -> OCIMetricsCounterHandler {
    OCIMetricsCounterHandler(id: OCIMetricsStreamID(kind: .counter, label: label, dimensions: [:]))
  }

  @Test("drain() reports the sum of increments since the last drain as a single sample with count 1")
  func drainReportsDeltaSum() {
    let handler = makeHandler()
    handler.increment(by: 3)
    handler.increment(by: 4)

    let samples = handler.drain()

    #expect(samples.count == 1)
    #expect(samples.first?.value == 7)
    #expect(samples.first?.count == 1)
  }

  @Test("a step in which the counter was never incremented reports nothing, not a zero")
  func idleStepReportsNothing() {
    let handler = makeHandler()
    #expect(handler.drain().isEmpty)
  }

  @Test("drain() resets the accumulator: a second consecutive drain reports nothing")
  func drainResetsAccumulator() {
    let handler = makeHandler()
    handler.increment(by: 10)
    _ = handler.drain()
    #expect(handler.drain().isEmpty)
  }

  @Test("increment(by: 0) still counts as a touched step and reports a 0 delta")
  func zeroIncrementIsATouchedStep() {
    let handler = makeHandler()
    handler.increment(by: 0)
    let samples = handler.drain()
    #expect(samples.count == 1)
    #expect(samples.first?.value == 0)
  }

  @Test("reset() discards the pending step's delta")
  func resetDiscardsPendingDelta() {
    let handler = makeHandler()
    handler.increment(by: 42)
    handler.reset()
    #expect(handler.drain().isEmpty)
  }

  @Test("increment(by:) wraps on overflow instead of trapping")
  func incrementWrapsOnOverflow() {
    let handler = makeHandler()
    handler.increment(by: .max)
    handler.increment(by: 1)
    let samples = handler.drain()
    #expect(samples.first?.value == Double(Int64.min))
  }
}

// MARK: - OCIMetricsRecorderHandler

struct OCIMetricsRecorderHandlerTests {
  private func makeRecorder(label: String = "latency", maximumSamples: Int = 1000) -> OCIMetricsRecorderHandler {
    OCIMetricsRecorderHandler(
      id: OCIMetricsStreamID(kind: .recorder, label: label, dimensions: [:]),
      aggregate: true,
      maximumSamples: maximumSamples
    )
  }

  private func makeGauge(label: String = "queue_depth") -> OCIMetricsRecorderHandler {
    OCIMetricsRecorderHandler(
      id: OCIMetricsStreamID(kind: .gauge, label: label, dimensions: [:]),
      aggregate: false,
      maximumSamples: 1000
    )
  }

  // MARK: Recorder (aggregate: true)

  @Test("an aggregating recorder collapses repeated identical values into one sample carrying the occurrence count")
  func aggregatingRecorderCollapsesDuplicates() {
    let recorder = makeRecorder()
    recorder.record(10.0)
    recorder.record(10.0)
    recorder.record(20.0)

    let samples = recorder.drain()

    #expect(samples.count == 2)
    #expect(samples[0].value == 10)
    #expect(samples[0].count == 2)
    #expect(samples[1].value == 20)
    #expect(samples[1].count == 1)
  }

  @Test("an aggregating recorder's samples are sorted ascending by value for deterministic request bodies")
  func aggregatingRecorderSortsAscending() {
    let recorder = makeRecorder()
    for value in [30.0, 10.0, 20.0] { recorder.record(value) }
    #expect(recorder.drain().map(\.value) == [10, 20, 30])
  }

  @Test("an aggregating recorder accepts Int64 values via the integer overload")
  func aggregatingRecorderAcceptsIntegers() {
    let recorder = makeRecorder()
    recorder.record(Int64(5))
    #expect(recorder.drain().first?.value == 5)
  }

  @Test("an aggregating recorder with nothing recorded reports nothing")
  func aggregatingRecorderIdleReportsNothing() {
    #expect(makeRecorder().drain().isEmpty)
  }

  @Test("drain() clears the aggregating recorder's occurrences: a second consecutive drain reports nothing")
  func aggregatingRecorderDrainResets() {
    let recorder = makeRecorder()
    recorder.record(1.0)
    _ = recorder.drain()
    #expect(recorder.drain().isEmpty)
  }

  @Test("an aggregating recorder drops new distinct values past maximumSamples but keeps counting repeats of tracked ones")
  func aggregatingRecorderBoundsDistinctValues() {
    let recorder = makeRecorder(maximumSamples: 2)
    recorder.record(1.0)  // tracked (1st distinct)
    recorder.record(2.0)  // tracked (2nd distinct, now at the bound)
    recorder.record(3.0)  // dropped: a 3rd distinct value exceeds the bound
    recorder.record(1.0)  // still counted: a repeat of an already-tracked value

    let samples = recorder.drain()

    #expect(Set(samples.map(\.value)) == [1, 2])
    #expect(samples.first { $0.value == 1 }?.count == 2)
    #expect(recorder.takeDroppedSamples() == 1)
  }

  @Test("an aggregating recorder drops NaN and ±Infinity instead of letting them reach JSONEncoder")
  func aggregatingRecorderDropsNonFiniteValues() {
    let recorder = makeRecorder()
    recorder.record(Double.nan)
    recorder.record(Double.infinity)
    recorder.record(-Double.infinity)
    recorder.record(1.0)

    #expect(recorder.drain().map(\.value) == [1])
    #expect(recorder.takeDroppedSamples() == 3)
  }

  @Test("repeated NaN observations do not exhaust an aggregating recorder's distinct-value budget")
  func aggregatingRecorderNaNDoesNotExhaustSampleBudget() {
    // NaN never compares equal to itself, so an unguarded recorder inserts a *new* dictionary
    // entry per observation and spends its whole budget on a value that cannot be encoded.
    let recorder = makeRecorder(maximumSamples: 2)
    for _ in 0..<100 { recorder.record(Double.nan) }
    recorder.record(7.0)
    #expect(recorder.drain().map(\.value) == [7])
  }

  @Test("takeDroppedSamples() resets to zero after being read")
  func takeDroppedSamplesResets() {
    let recorder = makeRecorder(maximumSamples: 1)
    recorder.record(1.0)
    recorder.record(2.0)  // dropped
    #expect(recorder.takeDroppedSamples() == 1)
    #expect(recorder.takeDroppedSamples() == 0)
  }

  // MARK: Gauge (aggregate: false)

  @Test("a gauge reports only the most recently set value")
  func gaugeReportsLastValue() {
    let gauge = makeGauge()
    gauge.record(5.0)
    gauge.record(7.0)
    #expect(gauge.drain().map(\.value) == [7])
  }

  @Test("a gauge repeats its last value on a step nobody touched, unlike a recorder")
  func gaugeRepeatsAcrossIdleSteps() {
    let gauge = makeGauge()
    gauge.record(5.0)
    #expect(gauge.drain().map(\.value) == [5])
    #expect(gauge.drain().map(\.value) == [5])  // still 5, not empty
  }

  @Test("a gauge refuses a non-finite value and keeps reporting its last finite one")
  func gaugeRefusesNonFiniteValue() {
    // `gauge.record(Double(errors) / Double(total))` with `total == 0` is the canonical way to get
    // a NaN into a gauge; without the guard the gauge would repeat it on every step forever, and
    // every request carrying it would fail to encode.
    let gauge = makeGauge()
    gauge.record(5.0)
    gauge.record(Double.nan)
    #expect(gauge.drain().map(\.value) == [5])
    #expect(gauge.takeDroppedSamples() == 1)
  }

  @Test("a gauge that was never set reports nothing")
  func gaugeNeverSetReportsNothing() {
    #expect(makeGauge().drain().isEmpty)
  }

  @Test("a gauge ignores maximumSamples: repeated set() calls never count as distinct occurrences")
  func gaugeIgnoresMaximumSamplesBound() {
    let gauge = OCIMetricsRecorderHandler(
      id: OCIMetricsStreamID(kind: .gauge, label: "queue_depth", dimensions: [:]),
      aggregate: false,
      maximumSamples: 1
    )
    for value in 0..<10 { gauge.record(Double(value)) }
    #expect(gauge.takeDroppedSamples() == 0)
    #expect(gauge.drain().map(\.value) == [9])
  }
}

// MARK: - OCIMetricsTimerHandler

struct OCIMetricsTimerHandlerTests {
  private func makeTimer(maximumSamples: Int = 1000) -> OCIMetricsTimerHandler {
    OCIMetricsTimerHandler(
      id: OCIMetricsStreamID(kind: .timer, label: "latency", dimensions: [:]),
      maximumSamples: maximumSamples
    )
  }

  @Test("recordNanoseconds(_:) reports the duration as-is, with no unit scaling")
  func recordsRawNanoseconds() {
    let timer = makeTimer()
    timer.recordNanoseconds(1_500_000)
    #expect(timer.drain().first?.value == 1_500_000)
  }

  @Test("a timer collapses identical durations into one sample with an occurrence count, like an aggregating recorder")
  func timerCollapsesDuplicateDurations() {
    let timer = makeTimer()
    timer.recordNanoseconds(100)
    timer.recordNanoseconds(100)
    timer.recordNanoseconds(200)

    let samples = timer.drain()

    #expect(samples.count == 2)
    #expect(samples.first { $0.value == 100 }?.count == 2)
    #expect(samples.first { $0.value == 200 }?.count == 1)
  }

  @Test("a timer with nothing recorded reports nothing")
  func idleTimerReportsNothing() {
    #expect(makeTimer().drain().isEmpty)
  }

  @Test("a timer delegates its distinct-duration bound to the underlying aggregating recorder")
  func timerDelegatesMaximumSamplesBound() {
    let timer = makeTimer(maximumSamples: 1)
    timer.recordNanoseconds(1)
    timer.recordNanoseconds(2)  // dropped: exceeds the bound
    #expect(timer.drain().count == 1)
    #expect(timer.takeDroppedSamples() == 1)
  }
}
