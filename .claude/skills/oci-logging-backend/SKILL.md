---
name: oci-logging-backend
description: Enable OCILogHandler so an application's swift-log records ship to OCI Logging via PutLogs — prerequisites and IAM, the LoggingSystem.bootstrap composition, the full OCILogHandlerConfiguration surface, batcher lifecycle and shutdown flushing, and how to tell whether delivery actually works. Use when asked to "ship my app logs to OCI Logging", "set up OCILogHandler", "bootstrap the OCI swift-log backend", "flush logs on shutdown", or "my logs never show up in OCI Logging".
---

# Enable the OCI Logging backend

Wire `OCILogHandler` (a swift-log `LogHandler`) into an application so plain `Logger`
calls land in an OCI custom log. Ground truth
`Sources/OCIKit/services/LoggingIngestion/`; signer/IAM per runtime
`docs/observability-deployment.md` §2–§3; a deployed, verified consumer
`oci-swift-sdk-examples/swift-oke/Sources/App/main.swift`.

## 1. Confirm the prerequisites — none are validated at runtime

- **A custom log OCID.** Log group and log are control-plane resources OCIKit has no
  client for; create them (Console → Logging, Terraform, CLI) and pass the OCID. A
  bogus one constructs happily and then fails *silently* at flush time.
- **IAM `LOG_CONTENT_PUSH`**: `Allow dynamic-group <dg> to use log-content in compartment
  <compartment>` (OKE workload identity: `any-user` plus `request.principal.*`
  conditions). Equally silent when missing; on Functions the principal's token caches
  ~15 min, so a policy edit is not live at once.
- **A signer** — any OCIKit signer, and on a cloud runtime the app's own.

## 2. Build the batcher, then bootstrap swift-log

```swift
// Optional on purpose — built only when the log OCID is configured, so the app still
// starts console-only without one and the `guard let` below composes. `init` starts the
// drain + ticker tasks at once: live from construction, never reclaimed implicitly.
let batcher: OCILogBatcher? = try logId.map { logId in   // logId: String?
  try OCILogBatcher(   // throws only `.missingRequiredParameter`: no region, no endpoint
    configuration: OCILogHandlerConfiguration(
      logId: logId, source: podName,  // source: NOT hostName — see the checklist
      type: "com.example.orders", subject: "order-service"),
    region: .phx, signer: signer)     // or `endpoint:` instead of `region:`
}
```

Build it first: swift-log makes one `OCILogHandler` per label, all sharing this batcher.

```swift
LoggingSystem.bootstrap { label in
  var console = StreamLogHandler.standardOutput(label: label)
  console.logLevel = logLevel
  // Keep the console handler: it is how you debug the process when the OCI half is
  // the broken half. Had you built the batcher into a `var`, copy it to a `let`
  // first — this closure is `@Sendable` and cannot capture a `var`.
  guard let batcher else { return console }
  return MultiplexLogHandler([
    console, OCILogHandler(label: label, batcher: batcher, logLevel: logLevel),
  ])
}
```

swift-log latches its factory on the first call and **traps on a second**, so a batcher
missing at bootstrap can only be added by restarting. Bootstrap before any framework
builds its own `Logger` (Hummingbird, Vapor), or that logger keeps the pre-bootstrap
console handler forever. The SDK never bootstraps; `log(...)` only renders and hands off.

## 3. Tune the configuration

All optional but `logId`; out-of-range values are clamped, not rejected. Per-field
semantics: `.../LoggingIngestion/OCILogHandlerConfiguration.swift`.

```swift
OCILogHandlerConfiguration(
  logId: "ocid1.log.oc1.phx.EXAMPLE",  // required; the only one
  source: podName,              // default `defaultSource` = this machine's hostname
  type: "oci-swift-sdk.application",   // default: `defaultType`; `subject:` defaults to nil
  flushInterval: 5,             // seconds; 0 (negative → clamped) disables the ticker
  flushSizeThreshold: 1 << 20,  // 1 MiB of buffered UTF-8 forces a flush
  bufferCapacity: 10_000,       // records in the hand-off buffer
  maxEntryLength: 9_900,        // clamped into 1...10_000
  requestTimeout: 10,           // seconds per attempt; 0 → transport default (60 s)
  retryConfig: RetryConfig(maxAttempts: 3, baseDelay: 0.5, maxDelay: 5, maxCumulativeDelay: 10),
  excludedLoggerLabels: ["myapp.noisy"])  // unioned with ["OCIKit"], never replacing it
```

- **`maxEntryLength` exists because the service truncates silently**: `data` over
  10,000 chars returns 200 and is stored cut to 10,000, so the batcher splits longer
  records into consecutive entries — `submitted` counts entries, not records.
- **`flushInterval` is your ingestion lag** — 0.76–4.25 s end to end at the 5 s default.
  `flushSizeThreshold` is ergonomics: `PutLogs` takes 1 MiB → 1 GiB with no silent drops.
- **`requestTimeout` × `retryConfig` bounds `shutdown()`** at
  `maxAttempts × requestTimeout + maxCumulativeDelay` — 40 s by default; shrink both
  for a tighter grace period.
- **`excludedLoggerLabels` is the label half of the recursion guard**: it is *unioned*
  with `["OCIKit"]` — the SDK's global `logger`, written on every signing pass — so it
  cannot be removed; a task-local `isFlushing` drops whatever a flush itself logs.

## 4. Flush on shutdown, or lose the buffer

`shutdown()` stops accepting records, drains the stream, uploads the rest, ends both
tasks; idempotent. Skipping it loses up to `bufferCapacity` records — including the ones
explaining why the process is going away. (`flush()` is the mid-life equivalent.) Use the
service lifecycle, not a signal handler: swift-service-lifecycle 2.x is a dependency of
*your* package — OCIKit does not ship it — and you `import ServiceLifecycle`.

```swift
// `Service` in full: `import OCIKit` also brings one in (the OCI service catalogue).
struct TelemetryFlushService: ServiceLifecycle.Service {
  let batcher: OCILogBatcher
  let logger: Logger

  func run() async throws {
    try await gracefulShutdown()   // parks here until the group starts shutting down
    await batcher.shutdown()       // waits for the final PutLogs
    // Past shutdown the handler discards records and counts them in `dropped`, so
    // this reaches the console only. (`metadata:` is an autoclosure — read first.)
    let stats = batcher.statistics
    logger.info("log drained", metadata: ["submitted": .stringConvertible(stats.submitted)])
  }
}

// A `ServiceGroup` tears down in REVERSE array order — put the flush service FIRST
// so it drains LAST, once the server has stopped and logged its final line.
let group = ServiceGroup(services: [flush, server], gracefulShutdownSignals: [.sigterm], logger: logger)
```

## 5. Verify — `statistics` is the only signal

**Delivery failures are never thrown and never logged** — a log backend cannot report
its own errors through the system it implements without recursing, so the batcher
swallows them into counters. A wrong log OCID, a missing `use log-content`, an
unreachable endpoint: all indistinguishable from a healthy app. Surface
`batcher.statistics` (a `nonisolated` snapshot, no `await`) where an operator reads it:

```swift
let stats = batcher.statistics
return [
  "log.enqueued": .stringConvertible(stats.enqueued),    // accepted into the buffer
  "log.submitted": .stringConvertible(stats.submitted),  // entries the service accepted
  "log.dropped": .stringConvertible(stats.dropped),      // buffer full, or post-shutdown
  "log.failed": .stringConvertible(stats.failed),        // entries permanently lost
  "log.flushFailures": .stringConvertible(stats.flushFailures),
  "log.lastFlushError": .string(stats.lastFlushErrorDescription ?? "none"),
] as Logger.Metadata
```

`dropped > 0` — `bufferCapacity` too small for the burst rate, flushes stalling, **or
the record was logged after `shutdown()`**, which is expected on a clean exit; the
buffer keeps the *oldest* records, so a drop discards the newest. `flushFailures > 0`
with `failed == 0` — failing but recovering: a failed batch goes back to the head of the
buffer, and with **no timestamp-skew rejection** it survives an outage for days (bounded
by the log's retention) and still lands at its claimed time, so the drop policy is
capacity- and never staleness-driven. `failed > 0` — the backlog outgrew
`bufferCapacity`, or `shutdown()`'s final flush failed with nothing left to retry it.
`lastFlushErrorDescription` carries the raw response body: reduce it to the error's case
name before serving it unauthenticated. For a probe with none of this machinery, call
`LoggingIngestClient.putLogs` as `Tests/Services/LoggingIngestionLiveTest.swift` does.

## Checklist

- [ ] Custom log exists, its OCID is configuration rather than a literal, and
      `use log-content` is granted to the workload's principal in that compartment.
- [ ] Batcher constructed **before** `LoggingSystem.bootstrap`, and once; console handler
      kept in the `MultiplexLogHandler` for local debugging.
- [ ] `flushInterval`/`requestTimeout`/`retryConfig` fit the termination grace period.
- [ ] Flush service **before** the server in `ServiceGroup(services:)` — reverse-order
      teardown then drains it after the server has stopped.
- [ ] `statistics` surfaced somewhere — it is the only delivery signal.
- [ ] `source` is **not** `hostName` on OKE virtual nodes: it (and `HOSTNAME`) is
      `localhost` there, so every replica reports one name. Use the downward API.
- [ ] Entries confirmed in OCI with `oci logging-search search-logs`.
