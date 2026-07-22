# OCIKit Service Roadmap

*Audit date: July 2026. Method: a multi-agent audit of all 171 modules in the reference
Python SDK (`oci-python-sdk`), triaged against this project's focus, with a deep dive into
every module that survived triage (23 candidates). Priorities below reflect maintainer
review of the audit (2026-07-16). Work that has since shipped keeps its entry in place,
marked **shipped** with a date, and is also listed under **Already implemented** — the audit
verdicts stay readable, the inventory stays current.*

## Guiding principle

OCIKit exists to let Swift developers **use** OCI services at runtime — not to mirror the
Python SDK. Two audiences drive every decision:

1. **Server-side Swift** (Vapor/Hummingbird/etc.) running on OCI compute, containers, or OKE,
   authenticating via instance/resource principals.
2. **iOS/macOS apps** talking to OCI directly (or internal ops/admin tools on Apple platforms).

That means **data-plane APIs only**: operations an application performs while running —
read/write data, publish/consume messages, invoke, query, encrypt/decrypt, ingest, run
inference. Control-plane APIs (provisioning and lifecycle of infrastructure) stay out of
scope; that is Terraform/Python/console territory.

Two recurring OCI nuances shaped this audit:

- **Managed data stores** (MySQL HeatWave, PostgreSQL, Redis/OCI Cache, OpenSearch, Managed
  Kafka, File Storage, Autonomous DB): the OCI REST API is control-plane only — the real
  data plane is the native wire protocol, reached with existing native drivers. Excluded
  regardless of popularity.
- **Alternative-protocol services** (Queue via STOMP, Streaming via Kafka compatibility):
  where a native-protocol Swift client exists —
  [swift-kafka-client](https://github.com/swift-server/swift-kafka-client) for Streaming,
  [stomp-nio](https://github.com/fpseverino/stomp-nio) for Queue — prefer documenting that
  path over porting the REST wrapper. Shared caveat: both protocols authenticate with static
  auth tokens, not instance/resource principals.

## Audit summary

| Verdict | Count |
|---|---|
| Tier 1 — high priority | 3 (1 shipped 2026-07) |
| Tier 2 — medium priority | 2 |
| Backlog — low priority | 16 (1 partially shipped 2026-07) |
| Already implemented | 9 services + auth signers |
| Control-plane only (excluded) | 109 modules |
| Low value (excluded, reasons below) | 29 modules |
| Not a service (helpers) | 3 modules |

**Already implemented:** ObjectStorage, Secrets (bundle retrieval), AI Language,
Generative AI Inference, IAM/Identity (partial), Container Instances, Functions (invoke
client + the `OCIKitFunctions` FDK), Logging Ingestion (`putLogs` + the `OCILogHandler`
swift-log backend), Monitoring (ingestion only — `postMetricData` + the `OCIMetricsFactory`
swift-metrics backend; the query ops stay in the backlog) — plus the auth core: API key
signer, instance principal, resource principal v2.2, OKE workload identity, security token
signer.

---

## Tier 1 — High priority

### 1. Logging Ingestion (`loggingingestion`) + swift-log backend — shipped 2026-07

- **Status: shipped 2026-07** (observability initiative, epic #85 —
  [OBSERVABILITY.md](OBSERVABILITY.md)), live-verified against a real tenancy and a real OKE
  cluster. Still open from that epic: the swift-log 1.14 / `LogEvent` follow-up (#87). Not in
  scope and still backlog: Logging Search, Log Analytics.
- **Ops (1):** `putLogs` — push batched `LogEntry` records to a Custom Log OCID.
- **Why:** before this landed, a Swift service on OCI had no first-party way to get
  structured logs into OCI Logging/Log Search/Alarms except stdout-scraping by the platform
  agent.
- **The deliverable was two layers, and the second was the essential one — both shipped:**
  1. the raw `putLogs` client (`LoggingIngestClient`, one op, three tiny models);
  2. an **`OCILogHandler`: a swift-log `LogHandler` backend** that batches log records
     in-memory (in the `OCILogBatcher` actor) and flushes them to `putLogs` on a
     size/interval threshold, plus an explicit flush on shutdown. This is what makes adoption
     zero-friction — apps already using swift-log (including this SDK itself) point their
     `LoggingSystem` bootstrap at OCI and are done. Design attention, as required: the
     handler does not log its own failures recursively, and flushing is actor-isolated
     (no GCD).
- **Cost/quirks:** dedicated host `ingestion.logging.{region}` — shipped as its own
  `.loggingingestion` case in `Region+Service.swift`. The `logging` (log-group CRUD) module
  stays out of scope.
- **Expanded 2026-07 by the observability initiative ([OBSERVABILITY.md](OBSERVABILITY.md),
  #85):** shipped together with the promoted Monitoring `postMetricData` slice + an
  `OCIMetricsFactory` swift-metrics backend (decisions recorded there, incl. the approved
  `swift-metrics` core dependency, now in `Package.swift`). The rest of Monitoring stays
  backlog.
- **Tracing needed no client, and none was built.** OCI APM ingests OTLP/HTTP with
  `Authorization: dataKey` auth (not OCI-signed), so the deliverable was a documented
  swift-otel recipe rather than a service client — shipped as
  [docs/observability-deployment.md](docs/observability-deployment.md) (per-runtime guide:
  which signer, which IAM policy, which endpoint) plus the standalone
  [apm-tracing](https://github.com/kicsipixel/oci-swift-sdk-examples/tree/main/apm-tracing)
  package in the examples repo, where swift-otel is an example-only
  dependency the SDK itself never takes. SDK-side work was limited to the `OCIKitFunctions`
  tracing-context fixes (#86): raw invocation headers, `TracingContext`, and the
  `APMCollectorEndpoint` collector-URL parser. The original audit could not surface the APM
  upload endpoint at all, because it is not a module in any language SDK; APM trace *query*
  remains excluded (see Excluded section).

### 2. Email Delivery — Data Plane (`email_data_plane`)

- **Ops (2):** `submitEmail` (JSON: sender, to/cc/bcc, subject, HTML+text bodies, returns
  suppressed recipients) and `submitRawEmail` (pre-built RFC 5322 MIME bytes).
- **Why:** transactional email (signup confirmation, password reset, receipts) sent straight
  from a Swift backend with instance/resource principal auth — a textbook audience-1 fit. The
  OCI service itself splits submission (`email_data_plane`) from sender/domain/DKIM management
  (`email`, control-plane, skip), so the port is clean.
- **Cost/quirks:** dedicated host `cell0.submit.email.{region}`. `submitRawEmail` passes
  metadata via headers (recipients comma-joined into one header). ~6 flat Codable models —
  Secrets-sized effort.

### 3. Identity Data Plane (`identity_data_plane`)

- **Ops (2):** `generateUserSecurityToken` (mint/refresh a UPST with an ephemeral RSA
  keypair) and `generateScopedAccessToken`.
- **Why:** this improves the SDK's **own auth story** rather than adding a service: the
  shipped `SecurityTokenSigner` can only consume a token written by `oci session
  authenticate` and cannot self-refresh, so delegated-user sessions silently die after
  ~60 minutes. `generateUserSecurityToken` closes that gap (a refresh loop swapping fresh
  UPSTs into the signer). `generateScopedAccessToken` is the REST half of OCI's IAM database
  authentication pattern.
- **Cost/quirks:** two trivial JSON POSTs, no pagination. Dedicated host `auth.{region}` —
  the same host family the instance-principal federation client already targets.

---

## Tier 2 — Medium priority

### KMS Crypto (`key_management`, `kms_crypto_client` only)

- **Ops (5–6):** `encrypt`, `decrypt`, `generateDataEncryptionKey`, `sign`, `verify`
  (+ `exportKey` if trivial). All flat POSTs — the simplest service shape in the audit.
- **Why:** envelope encryption of sensitive fields (DEK from KMS + local swift-crypto
  AES-GCM), webhook/JWT signing, signature verification. Natural sibling to Secrets.
- **Cost/quirks:** requires the vault's per-resource **crypto endpoint** (caller-supplied,
  same override pattern). The other four KMS clients (vault/management/HSM/EKM, ~8,000 lines
  of Python) are pure control-plane — skip.

### Certificates (`certificates`)

- **Ops (5, all read-only):** `getCertificateBundle` (incl. private-key variant),
  `getCaBundle`, `getCertificateAuthorityBundle`, plus two version-list ops.
- **Why:** the TLS-material analog of Secrets — fetch a server cert + key at startup to build
  `NIOSSLServerConfiguration`, fetch CA bundles for mTLS trust, poll versions to hot-swap on
  rotation. 100 % of the module is data-plane.
- **Cost/quirks:** near-clone of the Secrets service in size and shape. `CertificateBundle`
  is polymorphic on `certificateBundleType` — same discriminator pattern as
  `SecretBundleContentDetails`. No pagination anywhere. (`certificates_management` is
  control-plane, skip.)

---

## Backlog — Low priority

Genuinely in-scope data-plane surfaces, deferred until demand appears. Kept here with their
audit findings so they can be picked up without re-research.

### Deferred with an explicit alternative

- **Queue (`queue`)** — the strongest data-plane surface in the audit (produce / long-poll
  consume / ack / visibility on a durable queue — the canonical decoupled-worker pattern),
  but OCI Queue also speaks **STOMP 1.0–1.2 over raw TCP** (port 61613 on the queue's
  `messagesEndpoint`), and [stomp-nio](https://github.com/fpseverino/stomp-nio) (SwiftNIO,
  TLS, cross-platform incl. iOS via NIOTransportServices, MIT) covers that: SEND/SUBSCRIBE/
  ACK/NACK map to produce/consume/delete/visibility-update, with auth done once per
  connection instead of signing every HTTP request. Preferred path: validate stomp-nio
  against OCI Queue in a short spike (auth-token CONNECT, channel/consumer-group destination
  syntax) and publish a recipe/example. Caveats to document: STOMP auth is **auth-token
  only** (no instance/resource principals), no `getStats`/`listChannels`, only
  `client-individual` ack mode, and stomp-nio is a young single-author package. Revisit the
  REST wrapper only if principal auth or queue-stats demand appears.
- **Streaming (`streaming`)** — the REST data-plane ops (`putMessages`/`getMessages`/
  cursors/consumer groups) are real, but OCI Streaming exposes a **Kafka-compatible
  endpoint**, and [swift-server/swift-kafka-client](https://github.com/swift-server/swift-kafka-client)
  (SSWG, wraps librdkafka, macOS/Linux) already covers it via SASL_SSL/PLAIN with an auth
  token. Server-side users should use that; document the recipe rather than porting the REST
  wrapper. Revisit only for a use case the Kafka path can't serve (e.g. an iOS producer,
  where librdkafka is impractical — though mobile streaming is an anti-pattern anyway).
  Caveat to document: Kafka-compat auth is static auth tokens, not principals.

### AI family

- **AI Vision (`ai_vision`)** — `analyzeImage`/`analyzeDocument` are clean single-shot
  inference ops mirroring `ai_language`, and the mobile story (receipt/ID scanning) is nice —
  but it is a niche service without broad adoption. Low.
- **AI Document Understanding (`ai_document`)** — richer document-type presets than Vision's
  `analyzeDocument`; overlaps it. Only if document-AI demand appears.
- **AI Speech (`ai_speech`)** — `synthesizeSpeech` (streamed audio bytes), voice catalog,
  batch transcription via Object Storage. Realtime STT is a bespoke WebSocket protocol —
  unreliable on Linux, defer indefinitely.
- **GenAI Agents Runtime (`generative_ai_agent_runtime`)** — session CRUD + `chat` (RAG
  agents with citations/tool calls). The REST API genuinely is the data plane; if ever
  built, non-streaming `chat` only (SSE streaming is a non-goal, see cross-cutting notes).
  Revisit if OCI GenAI Agents gain traction.
- **Model Deployment (`model_deployment`)** — `predict`/`predictWithResponseStream`, opaque
  passthrough; only helps orgs already running OCI Data Science deployments.
- **GenAI Data / NL2SQL (`generative_ai_data`)** — `generateSqlFromNl`; compelling demo,
  niche adoption.

### Observability

- **Monitoring (`monitoring`)** — `postMetricData` / `summarizeMetricsData` / `listMetrics`
  (3 of 18 ops; ingestion host differs: `telemetry-ingestion.*` vs `telemetry.*`).
  **`postMetricData` shipped 2026-07** with the observability initiative (Tier 1 #1 above —
  `MonitoringClient` + `OCIMetricsFactory`, see [OBSERVABILITY.md](OBSERVABILITY.md));
  `summarizeMetricsData`/`listMetrics` and the `telemetry.*` query host **remain backlog** —
  a dashboard/alarm-query surface, not app runtime, so they stay demand-gated. The module
  keeps its backlog entry for that unshipped half.
- **Logging Search (`loggingsearch`)** — one op, `searchLogs`; trivial companion to the
  now-shipped Logging Ingestion client when an ops-tooling story materializes. Unchanged by
  the 2026-07 observability work.
- **Log Analytics (`log_analytics`)** — only the curated slice (~9 of ~180 ops: three upload
  endpoints incl. an OTLP logs sink, plus query). Premium opt-in service, heavy onboarding.

### Data, storage, eventing, ops

- **NoSQL (`nosql`)** — `getRow`/`updateRow`/`deleteRow`/`query`/`prepareStatement`; REST is
  the genuine data plane (driver-free JSON document store). Main cost: an `AnyCodable`-style
  JSON value type for rows.
- **Generic Artifacts Content (`generic_artifacts_content`)** — 3 ops, get/put artifact bytes
  by path+version; ObjectStorage-shaped. Note: the sibling `artifacts` module is 100 %
  control-plane — the data plane lives here, on its own `generic.artifacts.{region}` host.
- **Database Tools Runtime (`database_tools_runtime`)** — `executeSql` over IAM-signed REST
  (no driver/wallet/private-subnet route); uniquely useful for iOS/macOS ops tools. Needs a
  pre-provisioned Database Tools Connection; polymorphic model surface (~8–10 models for a
  SYNCHRONOUS/STANDARD MVP).
- **Notifications / ONS (`ons`)** — one op that matters: `publishMessage` (SNS-Publish
  equivalent). Near-zero cost; despite the client's name, 7 of its 10 ops are subscription
  CRUD — skip those. Not a path to APNs.
- **Resource Search (`resource_search`)** — `searchResources` (structured/free-text tenancy
  queries); ops/governance tooling audience.

---

## Excluded — and why

- **Control-plane only (109 modules):** compute/VCN/volume provisioning (`core`), OKE
  (`container_engine`), Load Balancer, DNS, API Gateway, all `*_management` modules, Data
  Science lifecycle, GoldenGate, Events rule CRUD, Cloud Guard, budgets/limits/quotas,
  marketplace, OS Management, fleet management, etc. These are Terraform/console workflows;
  a running Swift app has no business calling them.
- **Managed data stores where the wire protocol is the real data plane:** `mysql`, `psql`,
  `redis`, `opensearch`, `managed_kafka`, `file_storage` (NFS), `lustre_file_storage`,
  `database`. Use native Swift drivers (PostgresNIO, MySQLNIO, RediStack, …) instead.
- **Container Registry (`container_registry`, `artifacts` image half):** actual push/pull is
  the Docker Registry v2 protocol, not the OCI SDK. Only if a concrete need for
  `get_access_token` glue emerges would a micro-client make sense.
- **Ops/admin/billing tooling (29 low-value modules):** audit event export, APM trace query,
  usage/cost APIs (`usage_api`, `osub_*`, `osp_gateway`), threat intelligence, announcements,
  support tickets (`cims`), vulnerability scanning, management dashboards — genuine read APIs,
  but for dashboards/SIEM/finance, not app runtime. (Only APM trace *query* is excluded; APM
  trace *ingest* is a separate, data-key-authenticated OTLP endpoint and shipped 2026-07 as a
  documented recipe — see Tier 1 #1.)
- **`oda` (Digital Assistant):** authoring/lifecycle only; no runtime chat endpoint exists in
  the Python module. Runtime chat for agents is covered by `generative_ai_agent_runtime`.
- **`encryption`:** a client-side crypto helper library in Python, not a REST service. A
  Swift equivalent (envelope-encryption helpers over KMS crypto) could be a nice utility
  layer *after* KMS Crypto ships, but it is a design task, not a port.

---

## Cross-cutting engineering notes

1. **Caller-supplied endpoints are a first-class pattern.** Functions (`invokeEndpoint`) and
   KMS (per-vault crypto endpoint) — and Queue/Streaming if their REST wrappers are ever
   built — use per-resource data-plane hosts. The `SecretsClient`-style `endpoint:` override
   is the right precedent — do **not** pull in control-plane clients just to resolve
   endpoints.
2. **New `Region+Service` entries needed** for dedicated hosts: `cell0.submit.email.*`,
   `auth.*` (identity data plane — already partially present via the federation client);
   later `telemetry.*` (Monitoring query), `generic.artifacts.*`, `query.*`. Added 2026-07:
   `ingestion.logging.*` (case `.loggingingestion`) and `telemetry-ingestion.*` (case
   `.monitoringingestion` — no `.oci.` segment, the same suffix divergence `objectstorage`
   already had).
3. **SSE response streaming: deliberately dropped.** OCI streams LLM responses as
   Server-Sent Events when `isStream: true` is set (the shipped generativeai client exposes
   the flag but buffers via `URLSession.shared.data(for:)`, so incremental delivery can't
   work today). Decision: not worth building — users who need streaming LLM UX will point
   OpenAI/Anthropic-compatible Swift client libraries at OCI's compatibility endpoints
   instead of using OCIKit for it. Keep `isStream` documented as "no token-by-token
   delivery"; revisit only if OCI ships streaming-only capabilities with no compatibility
   path (this also keeps Agent Runtime chat and Model Deployment streaming non-goals).
4. **Native-protocol alternatives beat REST wrappers when a Swift client exists.**
   Streaming → Kafka compatibility + swift-kafka-client; Queue → STOMP + stomp-nio. In both
   cases the deliverable is a documented, validated recipe (and caveats: static auth-token
   credentials, no principals) rather than a ported REST client.
5. **WebSockets remain blocked on Linux** (AI Speech realtime STT) — the same class of
   platform gap that blocked OKE Workload Identity, which has since been resolved by a
   platform-specific carve-out: the opt-in, NIO-backed `OCIKitWorkloadIdentity` product,
   which keeps that dependency off every consumer who doesn't ask for it. Realtime STT
   would need the same shape; revisit only if the carve-out is worth the cost.
6. **Raw-bytes request/response paths** (generic artifacts, speech audio, raw email MIME)
   should reuse the ObjectStorage `Data`-in/`Data`-out pattern rather than forcing JSON
   models — as the shipped `FunctionsInvokeClient` already does.

## Suggested sequencing

| Phase | Work | Rationale |
|---|---|---|
| 1 | Spike: stomp-nio ↔ OCI Queue recipe | Small surface, high leverage; validates the Queue-without-REST bet early |
| 2 | Observability ([OBSERVABILITY.md](OBSERVABILITY.md)): Logging Ingestion + `OCILogHandler`, Monitoring `postMetricData` + `OCIMetricsFactory`, APM tracing recipe — **shipped 2026-07**. Remaining in this phase: Email Data Plane | Production server-app table stakes: logs, metrics, transactional email — logs and metrics landed, email is what's left |
| 3 | Identity Data Plane (+ `SecurityTokenSigner` self-refresh integration) | Fixes a real limitation in shipped auth |
| 4 | KMS Crypto, Certificates | Security round-out (small, Secrets-shaped) |
| 5 | Backlog by demand (incl. swift-kafka-client ↔ Streaming recipe) | Audience-gated work |
