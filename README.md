# oci-swift-sdk
oci-swift-sdk is a Swift SDK for interacting with Oracle Cloud Infrastructure (OCI), designed to work seamlessly across Linux, macOS, and iOS platforms. It enables developers to build robust, cloud-native applications in Swift by providing comprehensive access to OCI services.

The project is community-supported and maintained by contributors who are passionate about Swift and cloud development. It is not affiliated with Oracle or Oracle Cloud Infrastructure, and it does not receive official support from Oracle.

## Why
I love Swift, I use OCI because it's good, and I'd like to use OCI services for my Swift projects. And because there is no OCI SDK for Swift as of today.  

## Approach
Support for OCI services is being added incrementally, starting with those currently required. Contributions to expand service coverage are welcome. If a specific service is needed, feel free to implement it and submit a pull request so others can benefit from the addition as well.

## TODO List
- [x] API Key authN
- [x] GenAI inference (common models)
- [x] Instance Principal authN
- [x] Resource Principal authN (v2.2 — Container Instances, Functions, Data Science)
- [x] OKE Workload Identity authN (opt-in `OCIKitWorkloadIdentity` product — pins the in-cluster proxymux CA in-process)
- [x] Object Storage
- [x] Container Instances
- [x] GenAI inference (custom models)
- [x] Identity & Access Management (compartments)
- [x] Secrets (secret bundles)
- [x] AI Language (health entity detection)
- [x] Functions — run Swift as a function (FDK) + invoke a function
- [x] Logging Ingestion (`PutLogs`) + a batching swift-log backend

## Logging backend

`OCILogHandler` is a [swift-log](https://github.com/apple/swift-log) backend that ships your
application's log records to an OCI [custom log](https://docs.oracle.com/en-us/iaas/Content/Logging/Concepts/custom_logs.htm).
Bootstrap it once and the rest of the code keeps using plain `Logger` values.

```swift
import Logging
import OCIKit

let signer = try APIKeySigner(configFilePath: "~/.oci/config")
let batcher = try OCILogBatcher(
  configuration: OCILogHandlerConfiguration(
    logId: "ocid1.log.oc1.phx.EXAMPLE",   // an existing custom log
    type: "com.example.orders"
  ),
  region: .phx,
  signer: signer
)

LoggingSystem.bootstrap { label in
  MultiplexLogHandler([
    StreamLogHandler.standardOutput(label: label),
    OCILogHandler(label: label, batcher: batcher),
  ])
}

Logger(label: "com.example.orders").info("order placed", metadata: ["orderId": "1234"])

// Before the process exits, so buffered records are not lost:
await batcher.shutdown()
```

`log(...)` never blocks and never performs I/O: it renders the record and hands it to a bounded
buffer. An `OCILogBatcher` actor drains that buffer and uploads batches with `PutLogs` — on a size
threshold (1 MiB), on an interval (5 s), or when you call `flush()`/`shutdown()` — keeping at most
one request in flight. Messages longer than the service's 10,000-character truncation point are
split across entries. Anything logged from *inside* a flush is dropped rather than shipped —
whether it comes from the SDK's own logger or from your custom transport, signer, or retry code on
the request path — so a flush can never generate more logs to flush.

Records are lost in exactly two situations, both counted in `batcher.statistics` (a log backend
cannot report its own errors through the logging system it implements):

- **The buffer is full.** The newest record is dropped and counted in `statistics.dropped`. Raise
  `bufferCapacity` if you see this.
- **The backlog outgrows the buffer.** A failed flush is *not* discarded: its entries go back into
  the buffer and the next flush retries them, so records survive an outage (the service accepts
  entries as old as the log's retention window). Only when that backlog exceeds `bufferCapacity`
  are the oldest entries dropped, counted in `statistics.failed`. `statistics.flushFailures` and
  `statistics.lastFlushErrorDescription` report failures that were retried successfully too.

`shutdown()` waits for the final upload, so give it room in your termination grace period: at
worst `retryConfig.maxAttempts × requestTimeout + retryConfig.maxCumulativeDelay`, which is 40 s
with the defaults. Shorten `requestTimeout` or `retryConfig` if that is too long. A batch whose
*final* flush fails is lost, since nothing is left to retry it.

The log group and the log are control-plane resources: create them with Terraform, the OCI
Console, or the CLI, and pass the log's OCID. Your principal needs
`allow ... to use log-content in compartment ...`. To call `PutLogs` directly, use
`LoggingIngestClient`.

## OCI Functions

`OCIKitFunctions` is an opt-in [Function Development Kit](Sources/OCIKitFunctions/README.md)
that lets a Swift program run as an OCI Function (it serves the Fn `http-stream`
contract over a Unix socket). To call a deployed function from a Swift service,
`OCIKit` ships `FunctionsInvokeClient` (no extra dependencies). See the
[OCIKitFunctions guide](Sources/OCIKitFunctions/README.md) for writing, deploying,
and invoking functions.

## Metrics backend

`OCIMetricsFactory` is a [swift-metrics](https://github.com/apple/swift-metrics) backend that
publishes an application's metrics to [OCI Monitoring](https://docs.oracle.com/en-us/iaas/Content/Monitoring/Tasks/publishingcustommetrics.htm)
as custom metrics. Counters, gauges, recorders and timers are aggregated in process and posted
with `PostMetricData` on a 60-second step; requests are split at the service's 50-stream limit,
dimensions are sanitized, a default dimension is synthesized for metrics that have none, and data
points that age past the service's two-hour window are dropped and counted rather than retried.

```swift
import CoreMetrics
import OCIKit

let client = try MonitoringClient(region: .phx, signer: signer)
let factory = OCIMetricsFactory(
  client: client,
  configuration: try OCIMetricsConfiguration(
    namespace: "my_app",
    compartmentId: compartmentId,
    commonDimensions: ["service": "checkout", "env": "prod"]
  )
)
await factory.start()
MetricsSystem.bootstrap(factory)

// before the process exits, so the last step is not lost:
await factory.shutdown()
```

The SDK never calls `MetricsSystem.bootstrap` itself — the application owns the process-global
system and is free to multiplex this backend with another. The caller's principal needs
`allow ... to use metrics in compartment ...`, optionally narrowed with
`where target.metrics.namespace='<namespace>'`. Nothing on the export path throws; what was
published and what was lost is reported by `await factory.statistics()`.

## License

[MIT License](https://github.com/iliasaz/oci-swift-sdk/blob/main/LICENSE)

Copyright (c) 2024 Ilia Sazonov

_**Oracle** is a registered trademark of **Oracle Corporation**. Any use of their trademark is under the established [trademark guidelines](https://www.oracle.com/legal/trademarks.html) and does not imply any affiliation with or endorsement by them, and all rights are reserved by them._

_**Swift** is a registered trademark of **Apple, Inc**. Any use of their trademark does not imply any affiliation with or endorsement by them, and all rights are reserved by them._
