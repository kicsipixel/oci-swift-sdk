# OCIKit Observability Plan — logs, metrics, traces (OpenTelemetry)

Research and plan of action for epic [#85](https://github.com/iliasaz/oci-swift-sdk/issues/85),
which tracks the full work breakdown:
[#88](https://github.com/iliasaz/oci-swift-sdk/issues/88) `LoggingIngestClient`,
[#89](https://github.com/iliasaz/oci-swift-sdk/issues/89) `OCILogHandler`,
[#90](https://github.com/iliasaz/oci-swift-sdk/issues/90) `MonitoringClient`,
[#91](https://github.com/iliasaz/oci-swift-sdk/issues/91) `OCIMetricsFactory`,
[#86](https://github.com/iliasaz/oci-swift-sdk/issues/86) Functions tracing context,
[#92](https://github.com/iliasaz/oci-swift-sdk/issues/92) deployment guide + tracing example,
[#87](https://github.com/iliasaz/oci-swift-sdk/issues/87) swift-log 1.14 follow-up.
Status: **reviewed — §6 decisions resolved** (2026-07-21). Everything below is grounded in primary
sources (docs.oracle.com, official GitHub repos, the Python SDK) and — where documentation was
silent — **live probes run against a dev tenancy on 2026-07-21** (us-phoenix-1; temporary
resources created and deleted; marked "live-verified" throughout). Full research notes with
verbatim quotes and URLs are preserved in the session archive.

---

## 1. Problem statement

The roadmap's Phase 2 item covers logs only (Logging Ingestion + `OCILogHandler`). But logging
is one third of the observability story: a Swift service on OCI also needs **metrics** and
**distributed tracing**, and the ecosystem converges on **OpenTelemetry** as the lingua franca.

The server-side Swift API layer already exists — swift-log, swift-metrics,
swift-distributed-tracing, with swift-otel as the OTLP backend — but **no package anywhere
integrates them with OCI Logging, OCI Monitoring, or OCI APM**. A GitHub-wide search confirms:
no community Swift package ships telemetry to any OCI service. Whatever OCIKit builds here is
first of its kind.

The platform's collection agents don't close the gap either (§4): only VM file-tailing and
Functions invocation logs are agent-covered. On Container Instances **nothing** ships app logs;
app metrics and traces are self-export-only on **every** runtime.

## 2. What OCI can ingest (verified surfaces)

### 2.1 OCI Logging — `PutLogs` (the logs sink)

| Fact | Value |
|---|---|
| Request | `POST https://ingestion.logging.{region}.oci.oraclecloud.com/20200831/logs/{logId}/actions/push` |
| Body | `PutLogsDetails{specversion: "1.0", logEntryBatches: [LogEntryBatch]}`; batch = `{entries[], source, type, subject?, defaultlogentrytime}`; entry = `{data, id, time?}` (RFC3339 ms) |
| Auth | Standard OCI request signing — **all OCIKit signers work**. IAM: `allow ... to use log-content in compartment ...` (permission `LOG_CONTENT_PUSH`) |
| Response | HTTP 200, empty body |
| Models | Exactly three (confirmed against Python SDK `loggingingestion`): `PutLogsDetails`, `LogEntryBatch`, `LogEntry` |
| Prerequisite | An existing **custom Log OCID** (Log Group + Log are control-plane, out of scope — caller supplies the OCID) |
| Cost | $0.05/GB-stored/month, **first 10 GB/month free**; retention 30–180 days (30-day steps) |

Limits — documented and live-verified:

- Any log `data` field > 10,000 chars is **silently truncated** to exactly 10,000 ending in
  `...` (live-verified with 15 KB…2 MB entries — the documented "< 1 MB per entry" is not
  enforced as a rejection). The handler should split long messages client-side.
- **No practical payload cap**: 1 MiB → 1 GiB (106,893 entries) in a single request all
  returned 200 with **zero silent drops** (verified by Logging Search count read-back).
  Oracle's fluentd plugin caps batches at 9 MB — a client-side ergonomics choice, not a server
  limit. Flushes in the 1–10 MiB range remain sensible (retry amplification, upload latency).
- **No timestamp-skew rejection at all**: entries as old as the log's retention window land and
  index at their claimed time (−29 d OK at 30-day retention; −30.5 d returns 200 but is
  silently dropped); future timestamps accepted to at least +7 d. Practical consequence:
  **logs buffered across an outage survive for days** — there is no AWS-style staleness drop.
- UTF-8 only; structured JSON logs: ≤ 10,000 fields, names ≤ 128 B, values ≤ 10,000 B.

OCI Logging has **no OTLP endpoint** — an OTLP logs exporter cannot target it. (Logging
Analytics gained `UploadOtlpLogs` in Aug 2025, but it is OCI-signed — useless to a stock OTLP
exporter — and file/batch-oriented; a poor fit for a streaming LogHandler. Deep backlog.)

### 2.2 OCI Monitoring — `PostMetricData` (the metrics sink)

| Fact | Value |
|---|---|
| Request | `POST https://telemetry-ingestion.{region}.oraclecloud.com/20180401/metrics` — note: **no `.oci.` segment**, and a different host from the query-side `telemetry.{region}` |
| Body | `PostMetricDataDetails{metricData: [MetricDataDetails], batchAtomicity?}`; metric = `{namespace, resourceGroup?, compartmentId, name, dimensions, metadata?, datapoints[]{timestamp, value, count?}}` |
| Auth | OCI request signing. IAM: `allow ... to use metrics in compartment ... where target.metrics.namespace='<ns>'` (permission `METRIC_WRITE`) |
| Response | 200 + `{failedMetricsCount, failedMetrics[]}` — partial failures come back **inside a 200** (NON_ATOMIC default); 400 only when *all* metrics fail |
| Cost | First **500 M datapoints/month free**, then $0.0025 per million — effectively free |

Limits — documented and live-verified:

- **≤ 50 unique metric streams per request** (51 → 400 `"The valid range is 1 to 50"`,
  live-verified). Datapoints per stream effectively unbounded (2 M datapoints / 103 MiB in one
  request → 200, live-verified). 1–20 dimensions per metric. 50 TPS per tenancy.
- **Timestamps must be within (now − 2 h, now + 10 m)** — strictly enforced (live-verified
  exact error). Unlike logs, **metrics have a hard 2-hour outage budget**; older buffered
  datapoints are permanently unpostable.
- **`dimensions` must be non-empty** — `{}` or omitted → 400 `"dimensions can not be null or
  empty"` (live-verified). A swift-metrics backend **must synthesize a default dimension** for
  label-less metrics. Keys: no whitespace, ≤ 256 chars; values: non-empty, ≤ 512 chars.
- Namespace: starts alphabetical, `[A-Za-z0-9_]`, must not start with `oci_`/`oracle_`.

OCI Monitoring accepts **no OTLP and no Prometheus remote-write** (as of mid-2026). The only
write path is PostMetricData.

### 2.3 OCI APM — OTLP/HTTP ingestion (the traces sink)

APM is the one OCI service that speaks OpenTelemetry natively. Per APM domain (each domain has
a unique `dataUploadEndpoint` like `https://aaaabbbb.apm-agt.{region}.oci.oraclecloud.com`):

| Signal | Path (appended to `dataUploadEndpoint`) | Key |
|---|---|---|
| Traces | `/20200101/opentelemetry/public/v1/traces` or `/20200101/opentelemetry/private/v1/traces` | public or private |
| Metrics | `/20200101/opentelemetry/v1/metrics` | **private only** |
| Logs | — **no OTLP logs endpoint exists** | — |

- Auth is `Authorization: dataKey <key>` — **an APM data key, not OCI request signing**. No
  signer, no IAM policy, no OCIKit code needed on the hot path. A stock OTLP/HTTP exporter
  works unmodified (JSON or protobuf; OTLP/gRPC is not documented — treat as unavailable).
- Legacy Zipkin v2 path also exists:
  `/20200101/observations/{public-span|private-span}?dataFormat=zipkin&dataFormatVersion=2&dataKey=<key>`.
- Span links are not supported (dropped). Always Free: 1,000 tracing events/hour per tenancy.
- OTLP metrics sent to APM surface in OCI Monitoring under namespace `oracle_apm_monitoring` —
  a possible alternative metrics path, but it needs an APM domain + private key + swift-otel,
  and can't use OCI principals; not a substitute for first-party PostMetricData.

### 2.4 Functions tracing — live-verified runtime contract

With tracing enabled on an app+function, the runtime injects (live-verified by deploying an
env-dumping variant of `Tests/functions-live-test` with a fresh Always Free APM domain):

```
OCI_TRACING_ENABLED=1
OCI_TRACE_COLLECTOR_URL=<dataUploadEndpoint>/20200101/observations/public-span?dataFormat=zipkin&dataFormatVersion=2&dataKey=<PUBLIC data key>
```

plus per-invocation `X-B3-TraceId`/`X-B3-SpanId` headers (64-bit hex; no ParentSpanId/Sampled
on a direct invoke). The docs only show Zipkin clients — and Swift has no Zipkin tracer. But
the **parse-and-retarget path is live-verified**: parsing host + `dataKey` + visibility out of
that URL and POSTing an OTLP/HTTP JSON span to
`<host>/20200101/opentelemetry/public/v1/traces` with `Authorization: dataKey <key>` returned
200, and the span was queryable in Trace Explorer next to the platform's default
`function invocation` span. **A Swift function needs no Zipkin backend** — just a defensive
collector-URL parser (handle `public-span`/`private-span`; fall back to explicit config if the
shape ever changes) and any OTLP/HTTP exporter.

Found along the way — an FDK gap in this repo: for plain (non-HTTP-gateway) invokes,
`FunctionServer` drops all raw invocation headers
(`Sources/OCIKitFunctions/FunctionServer.swift:155`), so the X-B3 headers are invisible to
handlers today. Fix required regardless of the rest of this plan — tracked in
[#86](https://github.com/iliasaz/oci-swift-sdk/issues/86).

## 3. The Swift package landscape (what to build against)

| Package | Verdict | Why |
|---|---|---|
| apple/swift-log 1.14.0 | **build against (already a core dep)** | Zero-dep. New `LogEvent`-based handler path with bidirectional defaults; classic signature fully supported |
| apple/swift-metrics 2.11.0 | **build against** | **Zero dependencies**, no platforms block, NIO-free, `CoreMetrics` is even Foundation-free; strict-concurrency-complete; backends implement `MetricsFactory` (only counter/recorder/timer required — meter/FP-counter have defaults) |
| apple/swift-distributed-tracing 1.4.1 | **no OCIKit bridge needed** | Only dep is zero-dep swift-service-context — and **both are already pinned in Package.resolved** (pulled via async-http-client 1.30.1). But there is no OCI-*signed* trace sink to write a Tracer for; the OTLP path needs no OCIKit code |
| swift-otel 1.5.0 | **recipe/example only — never an OCIKit dep** | The server-side Swift OTLP backend (Apple + Vapor/Hummingbird contributors; Linux-first CI; all three signals; 1.x stable since 2025-09). Supports arbitrary endpoint + custom headers (`("authorization", "dataKey <key>")`) + per-signal backends + `onExportFailure` header rotation — the APM recipe needs zero OCIKit code. But it pulls **swift-nio even with all traits disabled** (`NIOConcurrencyHelpers`), and its exporter protocols are `internal` in 1.x — OCIKit *cannot* plug PutLogs/PostMetricData exporters into it |
| open-telemetry/opentelemetry-swift 2.5.0 | **rejected for server-side** | Apple-platform-centric (Jaeger/Zipkin/URLSession instrumentation Darwin-gated); OTLP/HTTP "still experimental", gRPC pinned to grpc-swift v1 `exact: 1.27.5` (conflict hazard); metrics on an outdated spec. Its own maintainers position swift-otel as the server-side choice |

Composition rule the whole plan follows: **OCIKit ships backends for the Apple API packages
(LogHandler, MetricsFactory); the app composes them** — via `LoggingSystem.bootstrap`,
`MetricsSystem.bootstrap`, `MultiplexLogHandler`, etc. An SDK library never bootstraps
process-global systems itself. Apps that want OTLP-everything can run swift-otel *alongside*
OCIKit backends (e.g. OTLP traces to APM + native PutLogs logs) — the multiplexing APIs make
mixing trivial.

## 4. Per-runtime reality: who collects what

Cell vocabulary — **Platform**: collected automatically, nothing to configure; **Agent**: a
platform agent the operator installs/configures; **App**: the process exports in-process via
SDK or OTLP — the paths this plan enables. Column headers link to the receiving service;
parentheses name the wire API.

| Runtime | Logs → [OCI Logging](https://docs.oracle.com/en-us/iaas/Content/Logging/home.htm) | App metrics → [OCI Monitoring](https://docs.oracle.com/en-us/iaas/Content/Monitoring/home.htm) | Traces → [OCI APM](https://docs.oracle.com/en-us/iaas/application-performance-monitoring/home.htm) | Injected principal (OCIKit signer) |
|---|---|---|---|---|
| Compute VM (incl. Always Free **A1.Flex** — agent live-verified RUNNING; the "not supported on A1" docs note is a stale pre-2022 doc bug) | Agent (Custom Logs file tailing) **or** App (`PutLogs`) | App (`PostMetricData`) | App (OTLP) | Instance principal (`InstancePrincipalSigner`) |
| Compute VM **E2.1.Micro** (Always Free x86) | App (`PutLogs`) — agent is shape-gated ("Not supported plugin is disabled for Shape VM.Standard.E2.1.Micro", 2022, unrefuted; 1 GB RAM argues against fluentd anyway) | App (`PostMetricData`) | App (OTLP) | Instance principal |
| OKE | Agent (Custom Logs on managed nodes, tailing `/var/log/containers/*`) **or** App (`PutLogs`) — no logging/OTel add-on exists | App (`PostMetricData`) | App (OTLP) — directly or via a self-managed OTel Collector | Workload identity, enhanced clusters (`OKEWorkloadIdentitySigner`); or node instance principal |
| **Container Instances** | App (`PutLogs`) — no agent or sidecar mechanism; platform is view-only (`RetrieveLogs`) | App (`PostMetricData`) | App (OTLP) | Resource principal v2.2 — exactly what `ResourcePrincipalSigner` implements (per-container opt-out flag `isResourcePrincipalDisabled`) |
| Functions | Platform (invocation logs, captures stdout/stderr) | App (`PostMetricData`) | Platform (default invocation span) **plus** App (OTLP, via parsed `OCI_TRACE_COLLECTOR_URL`) | Resource principal v2.2, env vars are file paths — refresh-safe with `ResourcePrincipalSigner` |

Supporting facts: no OTel Collector exporter for any OCI service exists upstream (the
`ocilogginganalyticsexporter` proposal was closed "not planned"); Oracle ships no collector
distro. Every runtime's principal maps onto a signer OCIKit already ships — **no new auth work
is needed anywhere in this plan.** Per-runtime IAM recipes (dynamic-group rules and policy
statements, verified against the policy references) are in the research notes and will go into
the deliverables' docs.

Precedents (what Oracle blesses elsewhere): Micronaut ships a logback appender over PutLogs
(batch 128, 100 ms period, logger-name blacklist for recursion) and a Micrometer registry over
PostMetricData (60 s step, batch 50); Helidon ships `OciMetricsSupport`; **every** language's
trace story is a generic OTLP/Zipkin exporter pointed at APM with a data key. No ecosystem
embeds an OTel SDK inside the OCI SDK. The plan below mirrors these shapes exactly.

## 5. The plan

### Phase 1 — Logs (roadmap Tier 1 #1, unchanged scope, now fully de-risked) — [#88](https://github.com/iliasaz/oci-swift-sdk/issues/88), [#89](https://github.com/iliasaz/oci-swift-sdk/issues/89)

**Core OCIKit, zero new dependencies.**

1. `Sources/OCIKit/services/LoggingIngestion/` — `LoggingIngestClient` (file
   `LoggingIngestion.swift`), `LoggingIngestionRouter.swift` (`enum LoggingIngestionAPI: API`,
   version `/20200831`, one case `putLogs(logId:)`), `Models/`: `PutLogsDetails`,
   `LogEntryBatch`, `LogEntry`, `LoggingIngestionError`. Client shape mirrors `SecretsClient`
   (`region:`/`endpoint:` init, `Signer`, `RetryConfig?`, injected `Logger`, `HTTPClient` seam).
2. `Region+Service`: `case loggingingestion` →
   `"ingestion.logging.\(region.urlPart).oci.oraclecloud.com"`.
3. **`OCILogHandler`** — swift-log backend + `OCILogBatcher` actor:
   - **Hand-off**: the sync `log(...)` hot path never blocks and never spawns per-record
     `Task`s (unbounded unstructured tasks, per-record allocation, lost ordering). It yields
     into a bounded `AsyncStream` — `continuation.yield` is synchronous and `Sendable`-safe,
     the buffering policy (`.bufferingOldest(capacity)`) provides the bounded buffer and
     overflow-drop semantics for free, and `yield`'s result reports drops so the handler can
     keep a dropped-record counter.
   - **Consumer**: the `OCILogBatcher` actor is the stream's single consumer. One long-lived
     drain task — owned by the batcher and cancelled deterministically in `shutdown()` —
     accumulates records and flushes on size threshold or interval tick
     (cancellation-cooperative `Task.sleep`); in-flight flushes are coalesced (the
     `OKEWorkloadIdentitySigner` idiom). Explicit `func flush() async` and
     `func shutdown() async` drain the buffer. No GCD, no semaphores, no `Task.detached`;
     all public types `Sendable` under strict concurrency.
   - **Recursion guard** (roadmap calls this out; now concretely mapped): core's global
     `logger` and `HTTPClient.send`'s debug logging would route through the bootstrapped
     LoggingSystem during a flush. The batcher's internal client gets a no-op/stderr logger;
     flush failures never `logger.error` into the handler itself. Logger-name blacklist à la
     Micronaut.
   - Sizing policy from the live probes: default flush ~every few seconds or ~1 MiB; split
     `data` > ~9,900 chars (silent server truncation at 10,000); bounded buffer with
     drop-oldest + a dropped-count counter; buffered logs are safe across long outages
     (retention-window bound, not hours).
   - Batch key: swift-log has no per-record source/subject — one `LogEntryBatch` per flush
     with configurable `source` (default hostname) / `type` / `subject`.
4. Tests: hermetic wire tests (request build + fixture replay), handler unit tests
   (batching, truncation-split, recursion guard, drop policy) — all credential-free, added to
   `UNIT_TEST_FILTER`; env-guarded live test.

### Phase 2 — Metrics (promote `postMetricData` out of backlog) — [#90](https://github.com/iliasaz/oci-swift-sdk/issues/90), [#91](https://github.com/iliasaz/oci-swift-sdk/issues/91)

**Deviation from the roadmap, made explicit:** ROADMAP files Monitoring under "Backlog —
deferred until demand appears". This initiative *is* the demand, and the promoted slice is
minimal: **`postMetricData` only** (1 of 18 ops; `summarizeMetricsData`/`listMetrics` and the
`telemetry.*` query host stay backlog). Cross-cutting note 2 already reserves the
`telemetry-ingestion.*` host entry.

1. `Sources/OCIKit/services/Monitoring/` — `MonitoringClient` (`Monitoring.swift`),
   `MonitoringRouter.swift`, `Models/`: `PostMetricDataDetails`, `MetricDataDetails`,
   `MonitoringDatapoint`, `PostMetricDataResponseDetails`, `FailedMetricRecord`,
   `MonitoringError`. Core OCIKit, zero new deps.
2. `Region+Service`: `case monitoringingestion` →
   `"telemetry-ingestion.\(region.urlPart).oraclecloud.com"` (no `.oci.` — precedent for
   suffix divergence already exists: `objectstorage`).
3. **`OCIMetricsFactory`** — swift-metrics backend, in **core OCIKit** (§6 decision 2):
   - **Hot path**: the handler classes (`CounterHandler`/`RecorderHandler`/`TimerHandler`)
     record synchronously into `Mutex`-guarded storage (`Synchronization` — already the house
     idiom), non-blocking and `Sendable`-clean; only counter/recorder/timer are required
     (meter and FP-counter have protocol-provided defaults).
   - **Exporter**: an actor snapshots the registry on a 60 s default step
     (Micronaut/Helidon precedent) from a single cancellation-cooperative `Task.sleep` loop
     owned by the actor and cancelled in `shutdown()`; flushes chunk to ≤ 50 streams,
     synthesize a default dimension for label-less metrics (server rejects empty dims),
     sanitize keys/values, drop-and-count datapoints older than 2 h, and parse
     `failedMetrics` inside 200s.
   - Config: `namespace` (required), `compartmentId` (required; from resource principal env
     where available), `resourceGroup?`, extra common dimensions.
4. Tests: same split as Phase 1.

### Traces — nothing to build (fixes tracked in [#86](https://github.com/iliasaz/oci-swift-sdk/issues/86))

There is **no OCI-signed trace sink**, APM ingestion is data-key-authenticated (§2.3), and
Functions already injects the collector URL + trace context at runtime (§2.4) — so OCIKit
ships no tracer, no trace client, and takes no swift-otel dependency. The only SDK work is
repairing omissions in `OCIKitFunctions`, tracked separately in
[#86](https://github.com/iliasaz/oci-swift-sdk/issues/86): the raw-header drop
(`FunctionServer.swift:155`), a `TracingContext` on `InvocationContext`, and a defensive
collector-URL parser. Beyond that, span upload is any OTLP/HTTP exporter's job (swift-otel),
covered by the Phase 3 recipe.

**Data-key distribution — no new SDK surface needed.** APM domain creation and data-key
generation/rotation are one-time **control-plane** operations (`apm-control-plane` 20200630,
via Console/CLI/Terraform — out of scope per the data-plane charter). At runtime, the
recommended pattern is: the operator stores the data key (and the domain's
`dataUploadEndpoint`) in a **Vault secret**, and the workload reads it at startup with the
existing `SecretsClient.getSecretBundle` under its injected principal — works today on every
runtime with zero new OCIKit code. On Functions, traces don't even need Vault: the platform
injects the public key via `OCI_TRACE_COLLECTOR_URL`; Vault matters there only for OTLP
*metrics* (private key, never injected) and on VM/OKE/Container Instances (where nothing
injects endpoint or key). The alternative — an `apm-control-plane` data-key client
(GetApmDomain/ListDataKeys) — stays backlog, and Vault remains the better default:
ListDataKeys returns the actual key **values** (live-verified), so any policy granting it is
as sensitive as the keys themselves.

### Phase 3 — Docs + examples — [#92](https://github.com/iliasaz/oci-swift-sdk/issues/92)

1. A per-runtime deployment guide (the §4 matrix + IAM recipes + which signer to construct),
   including the Always Free guidance (A1: agent or SDK; E2.1.Micro: SDK only).
2. **The traces recipe + example** (swift-otel as an *example-only* dep, standalone like
   `Tests/functions-live-test`): swift-otel `OTLPHTTP` →
   `<dataUploadEndpoint>/20200101/opentelemetry/{public|private}/v1/traces` with
   `headers: [("authorization", "dataKey <key>")]`; caveats: span links dropped, no OTLP
   logs, 1,000 events/hr on Always Free, B3 64-bit trace ids left-pad to 128-bit W3C.

## 6. Decisions (resolved by maintainer, 2026-07-21)

1. **Metrics promoted into the observability effort** — yes; the `postMetricData` ingestion
   slice only (`summarizeMetricsData`/`listMetrics` and the `telemetry.*` query host stay
   backlog). ROADMAP updated accordingly.
2. **`swift-metrics` dependency approved; `OCIMetricsFactory` lives in core OCIKit** — it is
   an Apple, zero-dep, NIO-free API package (lighter than anything core already carries), and
   a product boundary between `MonitoringClient` and its factory buys nothing.
3. **Client type name: `LoggingIngestClient`** (file `LoggingIngestion.swift`, directory
   `services/LoggingIngestion/`); `Service` cases `loggingingestion` / `monitoringingestion`.
4. **Classic `LogHandler` signature for now** — works across the whole swift-log 1.x line
   with no floor change. Updating the dependency to 1.14 and evaluating the `LogEvent` path
   is tracked in [#87](https://github.com/iliasaz/oci-swift-sdk/issues/87).
5. **ROADMAP reconciled** (same-day edit): promoted Monitoring slice noted in Tier 1 and in
   the backlog entry; APM-OTLP-recipe note added (the audit couldn't see the APM upload
   endpoint because it is not a module in any language SDK — the exclusion of APM trace
   *query* stands untouched); ROADMAP now references this document.
6. **Traces need no plan phase** — `OCIKitFunctions` fixes are tracked in
   [#86](https://github.com/iliasaz/oci-swift-sdk/issues/86); everything else is the Phase 3
   recipe.

## 7. Explicit non-goals

- No OTel Collector work, no swift-otel dependency in any OCIKit product.
- No log-group/alarm CRUD, no `SummarizeMetricsData`/`ListMetrics`, no APM trace query.
- No Logging Analytics (incl. its OTLP logs upload) — deep backlog, premium onboarding.
- No Prometheus endpoints/remote-write (OCI has no receive path).
- No process-global bootstrap inside OCIKit — apps own `LoggingSystem`/`MetricsSystem`.
