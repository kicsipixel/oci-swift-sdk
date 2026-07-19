// swift-tools-version: 6.2
// Live end-to-end test for OCI Functions:
//   relay-invoke (local CLI, API-key auth) -> OCI Function (relay-function,
//   Resource Principal auth) -> Object Storage.
//
// This example depends on oci-swift-sdk from GitHub so the function container can
// build it without the surrounding repo in its Docker context. Point it at `main`
// once the Functions support is merged.
import PackageDescription

let package = Package(
  name: "functions-live-test",
  platforms: [.macOS(.v15)],
  dependencies: [
    .package(url: "https://github.com/iliasaz/oci-swift-sdk.git", branch: "feature/oci-functions")
  ],
  targets: [
    // The OCI Function: reads an object with Resource Principal auth and returns it.
    .executableTarget(
      name: "relay-function",
      dependencies: [
        .product(name: "OCIKitFunctions", package: "oci-swift-sdk"),
        .product(name: "OCIKit", package: "oci-swift-sdk"),
      ]
    ),
    // The local client CLI: invokes the function with API-key auth.
    .executableTarget(
      name: "relay-invoke",
      dependencies: [
        .product(name: "OCIKit", package: "oci-swift-sdk")
      ]
    ),
  ]
)
