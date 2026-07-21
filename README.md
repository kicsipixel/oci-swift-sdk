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
