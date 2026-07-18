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
    .package(url: "https://github.com/apple/swift-configuration.git", from: "1.0.0"),
    // Only reached by the OCIKitWorkloadIdentity product's target graph.
    .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.21.0"),
    .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
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
        .product(name: "Configuration", package: "swift-configuration"),
      ]
    ),
    // The ONLY target that references async-http-client / swift-nio.
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
