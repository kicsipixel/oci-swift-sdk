---
name: oci-metrics-backend
description: Enable OCIMetricsFactory so an application's swift-metrics instruments (Counter/Gauge/Recorder/Timer) are published to OCI Monitoring as custom metrics via PostMetricData — construction, MetricsSystem.bootstrap, the configuration surface, IAM, shutdown, and verification. Use when asked to "send my metrics to OCI Monitoring", "bootstrap OCIMetricsFactory", "publish custom metrics from Swift", "wire swift-metrics to OCI", "why are my metrics not showing up in Monitoring", or "set up the metrics backend".
---

# Enable the OCI Monitoring metrics backend

Wire `OCIMetricsFactory` (`Sources/OCIKit/services/Monitoring/`) into an application so
`Counter`/`Gauge`/`Recorder`/`Timer` calls land in OCI Monitoring. The SDK never calls
`MetricsSystem.bootstrap` — the app composes. A deployed, verified consumer:
`oci-swift-sdk-examples/swift-oke/Sources/App/main.swift`.

## 1. Confirm the prerequisites

- **swift-metrics as a dependency of *your* package.** OCIKit builds against
  `CoreMetrics` and does not re-export the `Metrics` façade you record through: add
  `.package(url: "https://github.com/apple/swift-metrics.git", from: "2.11.0")` and
  `.product(name: "Metrics", package: "swift-metrics")`, or `import Metrics` fails.
- **A compartment OCID** — the only OCID you need; unlike logs there is nothing to create
  first, the namespace exists from the first accepted post.
- **A namespace** matching `^[a-z][a-z0-9_]*[a-z0-9]$`, ≤ 256 chars, not starting with
  `oci_`/`oracle_`. `swift_oke` is legal; `swift-oke`, `MyApp` and `my_app_` are not.
- **IAM `METRIC_WRITE`**, narrowed to the namespace: `Allow dynamic-group <dg> to use
  metrics in compartment <compartment> where target.metrics.namespace='my_app'`; other
  runtimes (including OKE workload identity's `any-user`) in
  `docs/observability-deployment.md` §3. A policy edit takes ~15 min to bite.
- **A signer** — any OCIKit `Signer`; on a cloud runtime the app's own.

## 2. Construct and bootstrap

```swift
import Metrics  // the façade you record through; OCIKit itself only imports CoreMetrics
import OCIKit

let factory = OCIMetricsFactory(
  client: try MonitoringClient(region: .phx, signer: signer),
  configuration: try OCIMetricsConfiguration(
    namespace: "my_app",          // validated eagerly — throws here, not at flush time
    compartmentId: compartmentId,
    commonDimensions: ["service": "checkout", "env": "prod"]),
  logger: Logger(label: "my_app.metrics"))  // default: Logger(label: "OCIMetricsFactory")

await factory.start()             // step loop first: instruments made earlier still register
MetricsSystem.bootstrap(factory)  // exactly once per process — a second call traps
```

Order matters twice. Bootstrap **after** `LoggingSystem.bootstrap`, so the factory's
logger writes through the finished logging system — unlike the log backend the exporter
has no recursion guard, so its warnings ship to OCI Logging like any other line, which
is why it deserves its own label. And **before** anything records: swift-metrics latches
the factory, and earlier instruments keep the previous, usually no-op, one forever.

## 3. The configuration surface

Every parameter with its real default (`OCIMetricsConfiguration.swift`):

```swift
try OCIMetricsConfiguration(
  namespace: "my_app", compartmentId: compartmentId, resourceGroup: nil,
  commonDimensions: ["service": "checkout", "env": "prod"],
  defaultDimensionName: OCIMetricsConfiguration.fallbackDimensionName,  // "source"
  defaultDimensionValue: podName,  // default: hostName → see the checklist
  step: .seconds(60),              // `Swift.Duration`: OCIKit exports an ObjectStorage `Duration`
  maximumBufferedStreams: 500,
  maximumSamplesPerStream: 1000)
```

- **`step`** — 60 s is Monitoring's minimum aggregation interval; shortening it spends
  the tenancy's 50 TPS `PostMetricData` budget and buys nothing.
- **`commonDimensions`** are sanitized once, here, and merged **over** an instrument's
  own dimensions on a collision: operator labels application code cannot shadow.
- **`maximumBufferedStreams`** bounds the *retry buffer only* — a step's fresh streams
  are always posted; overflow drops the oldest into `droppedBufferedStreams`.
- **`maximumSamplesPerStream`** is distinct values per recorder/timer per step; past it
  repeats of a seen value still count, new distinct values go to `droppedSamples`.

The initializer throws `OCIMetricsError` — `.invalidNamespace`, `.missingCompartmentId`,
`.invalidStep`, `.invalidBufferBound` — so catch it and degrade to no metrics rather than
failing to start. Names and dimensions are afterwards **coerced, not dropped**, by
`OCIMetricsSanitizer.swift`; the two rules it cannot rescue are yours: the namespace
above, and the 20-dimension cap (lexicographically-first keys survive).

## 4. What each instrument becomes

One metric object per stream per step; a stream is `kind + label + dimensions`.

| Instrument | Posted per step |
|---|---|
| `Counter`, `FloatingPointCounter` | one datapoint, the **delta** since the last step; an idle step posts nothing |
| `Recorder`, `Meter` | one datapoint per distinct value, carrying its occurrence `count` |
| `Gauge` | one datapoint: the last value set, repeated every step until it changes |
| `Timer` | as `Recorder`, in **nanoseconds**, with `metadata ["unit": "ns"]` |

Internalize the delta model: **cumulative totals come from the query**, not the counter —
`bytes_served_total[1m].sum()` over your window, which is what you want across restarts.
Idle streams cost nothing, and alarms read the gap as "no data" rather than zero.

```swift
let dims = [("route", route), ("method", method),  // route TEMPLATE; method allow-listed
            ("status_class", "\(status / 100)xx")]  // the class, never the exact code
Counter(label: "http_requests_total", dimensions: dims).increment()
Metrics.Timer(label: "http_request_duration", dimensions: dims)  // bare `Timer` is Foundation's
  .record(duration: ContinuousClock.now - start)
```

**Cardinality is the caller's job**: every distinct combination of values mints its own
stream, and streams cost requests, money and query legibility. Never dimension by raw
path, object name, user id, or anything caller-controlled. `NaN`/`±Inf` are refused at
the recording boundary and counted in `droppedSamples`.

## 5. Shut down without losing the buffer

`shutdown()` cancels the step task, **awaits** it, then flushes — nothing is in flight
when it returns. Skip it and a terminating pod loses up to a full step; worse, the step
task retains the factory, so dropping the reference does not stop it. (`flush()` publishes
mid-life without disturbing the cadence; the drain is destructive, so nothing posts twice.)
Needs swift-service-lifecycle 2.x as a dependency of *your* package.

```swift
struct MetricsFlushService: ServiceLifecycle.Service {  // `Service` in full: OCIKit exports one
  let factory: OCIMetricsFactory
  let logger: Logger
  func run() async throws {
    try await gracefulShutdown()  // parks until SIGTERM
    await factory.shutdown()
    let stats = await factory.statistics()
    logger.info("metrics drained", metadata: ["posted": .stringConvertible(stats.postedStreams)])
  }
}

// A `ServiceGroup` tears down in REVERSE array order — the flush service goes FIRST so it
// drains LAST. Listed after the server it flushes while the server is still draining, and
// everything recorded during that drain is accumulated and never posted.
let group = ServiceGroup(services: [flush, server], gracefulShutdownSignals: [.sigterm], logger: logger)
```

Budget the grace period: `MonitoringClient` defaults to `HTTPClient.live`, so an unanswered
`PostMetricData` inherits `URLSession`'s 60 s timeout and `shutdown()` can perform two.

```swift
// Linux's async `URLSession` shim ignores cancellation, so `timeoutInterval` is the only
// bound that binds. Pass it as `MonitoringClient(..., httpClient: bounded)`.
let bounded = OCIKit.HTTPClient { request in
  var request = request
  request.timeoutInterval = 5
  return try await OCIKit.HTTPClient.live.data(request)
}
```

## 6. Verify it is actually working

Nothing on the export path throws — but it is **not** silent, so read the app's own logs
first. The exporter logs every failure through the logger you handed it:
`[OCIMetricsExporter] postMetricData permanently rejected N stream(s) ...` (a missing
`use metrics` policy surfaces here as the 401/403 text), one `metric "x" rejected:
<service message>` per record refused **inside a `200`** (partial failures are reported in
the body, are permanent, are never retried), plus stale and retry-buffer drops;
`MonitoringClient.postMetricData` separately logs `[postMetricData] <code> (<status>):
<message>` on any non-200. `await factory.statistics()` is the only *counter* — surface
all seven (`postedStreams`, `postedDatapoints`, `failedMetrics`, `failedRequests`,
`droppedStaleDatapoints`, `droppedBufferedStreams`, `droppedSamples`); they are monotonic
and never reset. Then ask the service (allow 1–2 min):

```bash
oci monitoring metric list --compartment-id <compartment-ocid> --namespace my_app --all
oci monitoring metric-data summarize-metrics-data --compartment-id <compartment-ocid> \
  --namespace my_app --query-text 'http_requests_total[1m].sum()' \
  --start-time <iso8601> --end-time <iso8601>
```

`metric list` shows which streams exist and their dimension keys — the fastest way to
catch a cardinality mistake.

## Checklist

- [ ] swift-metrics on the app target; lower-case namespace chosen; `use metrics` policy
      in place and ≥ 15 min old.
- [ ] `OCIMetricsConfiguration` built in a `do`/`catch` — failure degrades to no metrics.
- [ ] `await factory.start()`, then `MetricsSystem.bootstrap(factory)` once, after
      `LoggingSystem.bootstrap` and before anything records.
- [ ] Flush service **before** the server in `ServiceGroup(services:)`; transport bounded
      with `timeoutInterval` if the runtime enforces a grace period.
- [ ] Dimensions bounded: route templates, status classes, allow-listed methods; `pod` and
      `defaultDimensionValue` from the downward API (`metadata.name`), never `HOSTNAME` —
      on OKE virtual nodes it is `localhost`, the trap `oci-logging-backend` also notes.
- [ ] Timestamps inside `(now − 2h, now + 10m)` — the entire outage budget (logs survive
      days, metrics do not); `droppedStaleDatapoints` counts what fell outside. And ≤ 50
      streams per request, which only direct `postMetricData` callers must enforce.
- [ ] Both failure signals watched: the app's own logs *and* `statistics()`.
