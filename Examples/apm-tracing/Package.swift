// swift-tools-version: 6.2
// Standalone example: exporting OpenTelemetry spans to OCI Application Performance
// Monitoring (APM) with swift-otel's OTLP/HTTP exporter.
//
// This package is deliberately NOT a target of the root oci-swift-sdk package —
// swift-otel must never enter the SDK's dependency graph (see OBSERVABILITY.md §3).
// It lives outside `Sources/` and `Tests/`, so SwiftPM at the repo root never scans
// it, and it depends on oci-swift-sdk from GitHub — not on the surrounding checkout —
// so the function container can build it without the repo in its Docker context.
//
// It tracks `main` rather than a release tag because it needs `OCIKitFunctions`'
// `TracingContext` / `APMCollectorEndpoint`; switch to `from: "<version>"` once a tag
// carrying them exists.
import PackageDescription

let package = Package(
  name: "apm-tracing",
  platforms: [.macOS(.v15)],
  dependencies: [
    .package(url: "https://github.com/iliasaz/oci-swift-sdk.git", branch: "main"),
    // Only the OTLP/HTTP trait is enabled: APM ingests OTLP over HTTP only, and
    // leaving OTLPGRPC off keeps grpc-swift out of the example's graph entirely.
    .package(url: "https://github.com/swift-otel/swift-otel.git", from: "1.5.0", traits: ["OTLPHTTP"]),
    .package(url: "https://github.com/apple/swift-distributed-tracing.git", from: "1.2.0"),
    .package(url: "https://github.com/swift-server/swift-service-lifecycle.git", from: "2.4.1"),
    .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
  ],
  targets: [
    // The reusable part of the recipe: APM endpoint composition, the swift-otel
    // configuration APM needs, and the B3 -> W3C trace-context bridge.
    .target(
      name: "APMTracing",
      dependencies: [
        .product(name: "OTel", package: "swift-otel"),
        .product(name: "Tracing", package: "swift-distributed-tracing"),
      ]
    ),
    // Any long-running workload (VM, OKE, Container Instances): endpoint and data
    // key come from configuration, spans go to APM over OTLP/HTTP.
    .executableTarget(
      name: "apm-trace-probe",
      dependencies: [
        "APMTracing",
        .product(name: "OTel", package: "swift-otel"),
        .product(name: "Tracing", package: "swift-distributed-tracing"),
        .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
        .product(name: "Logging", package: "swift-log"),
      ]
    ),
    // The OCI Functions variant: endpoint, data key and parent span come from what
    // the platform injects, via OCIKitFunctions' `TracingContext`.
    .executableTarget(
      name: "apm-trace-function",
      dependencies: [
        "APMTracing",
        .product(name: "OCIKitFunctions", package: "oci-swift-sdk"),
        .product(name: "OTel", package: "swift-otel"),
        .product(name: "Tracing", package: "swift-distributed-tracing"),
        .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
        .product(name: "Logging", package: "swift-log"),
      ]
    ),
  ]
)
