// swift-tools-version: 6.2
// Copyright 2024 Ilia Sazonov
// SPDX-License-Identifier: MIT License

import PackageDescription

let package = Package(
  name: "oci-swift-sdk",
  platforms: [
    .macOS(.v15),
    .iOS(.v18),
  ],
  products: [
    .library(name: "OCIKit", targets: ["OCIKit"]),
    // Opt-in add-on: the OCI Functions Development Kit (FDK). It lets a Swift
    // program run as an OCI Function by serving the Fn `http-stream` contract
    // over a Unix domain socket. It pulls in SwiftNIO, which the base SDK avoids,
    // so consumers who do not write functions never depend on this product —
    // per SPM's product-filtered resolution (SE-0226) they never fetch/build
    // swift-nio. The invoke-only `FunctionsInvokeClient` lives in core `OCIKit`
    // (no NIO) so any client can call a deployed function.
    .library(name: "OCIKitFunctions", targets: ["OCIKitFunctions"]),
    // Opt-in add-on: an in-process CA-pinning transport (AsyncHTTPClient + NIOSSL)
    // for OKE Workload Identity. Consumers who do not use OKE never depend on this
    // product, so — per SPM's product-filtered resolution (SE-0226) — they never
    // fetch or build async-http-client / swift-nio.
    .library(name: "OCIKitWorkloadIdentity", targets: ["OCIKitWorkloadIdentity"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-crypto.git", from: "3.2.0"),
    .package(url: "https://github.com/iliasaz/Perfect-INIParser.git", branch: "master"),
    .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
    .package(url: "https://github.com/apple/swift-metrics.git", from: "2.11.0"),
    .package(url: "https://github.com/apple/swift-configuration.git", from: "1.0.0"),
    // Only reached by the opt-in products' target graphs: the OCIKitFunctions
    // FDK (Unix-domain-socket HTTP/1.1 server) and the OCIKitWorkloadIdentity
    // CA-pinning transport.
    .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
    .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.21.0"),
    .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.27.0"),
  ],
  targets: [
    .target(
      name: "OCIKit",
      dependencies: [
        .product(name: "Crypto", package: "swift-crypto"),
        .product(name: "_CryptoExtras", package: "swift-crypto"),
        .product(name: "INIParser", package: "Perfect-INIParser"),
        .product(name: "Logging", package: "swift-log"),
        // A metrics *backend* (`OCIMetricsFactory`) builds against `CoreMetrics`,
        // not the `Metrics` façade — the façade is the API applications record
        // through, and depending on it from a backend would be circular.
        .product(name: "CoreMetrics", package: "swift-metrics"),
        .product(name: "Configuration", package: "swift-configuration"),
      ]
    ),
    // The FDK runtime — one of only two targets that reference swift-nio.
    .target(
      name: "OCIKitFunctions",
      dependencies: [
        "OCIKit",
        .product(name: "NIOCore", package: "swift-nio"),
        .product(name: "NIOPosix", package: "swift-nio"),
        .product(name: "NIOHTTP1", package: "swift-nio"),
        .product(name: "Logging", package: "swift-log"),
      ],
      exclude: ["README.md"]
    ),
    // The ONLY target that references async-http-client / swift-nio-ssl.
    .target(
      name: "OCIKitWorkloadIdentity",
      dependencies: [
        "OCIKit",
        .product(name: "AsyncHTTPClient", package: "async-http-client"),
        .product(name: "NIOCore", package: "swift-nio"),
        .product(name: "NIOHTTP1", package: "swift-nio"),
        .product(name: "NIOSSL", package: "swift-nio-ssl"),
      ]
    ),
    .testTarget(
      name: "Tests on Linux",
      dependencies: ["OCIKit"],
      path: "Tests/Linux"
    ),
    .testTarget(
      name: "OCIKitCoreTests",
      dependencies: ["OCIKit"],
      path: "Tests/OCIKit"
    ),
    .testTarget(
      name: "OCIKitServiceTests",
      dependencies: ["OCIKit"],
      path: "Tests/Services"
    ),
    .testTarget(
      name: "OCIKitFunctionsTests",
      dependencies: [
        "OCIKitFunctions",
        .product(name: "NIOCore", package: "swift-nio"),
        .product(name: "NIOPosix", package: "swift-nio"),
        .product(name: "NIOHTTP1", package: "swift-nio"),
      ],
      path: "Tests/OCIKitFunctions"
    ),
    .testTarget(
      name: "OCIKitWorkloadIdentityTests",
      dependencies: [
        "OCIKitWorkloadIdentity",
        .product(name: "NIOCore", package: "swift-nio"),
        .product(name: "NIOHTTP1", package: "swift-nio"),
      ],
      path: "Tests/WorkloadIdentity"
    ),
  ]
)
