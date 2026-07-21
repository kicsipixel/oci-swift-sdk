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
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-crypto.git", from: "3.2.0"),
    .package(url: "https://github.com/iliasaz/Perfect-INIParser.git", branch: "master"),
    .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
    .package(url: "https://github.com/apple/swift-configuration.git", from: "1.0.0"),
    // Only reached by the OCIKitFunctions product's target graph (the FDK's
    // Unix-domain-socket HTTP/1.1 server).
    .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
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
    // The ONLY target that references swift-nio: the FDK runtime.
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
  ]
)
