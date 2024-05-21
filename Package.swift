// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "oci-swift-sdk",
    platforms: [
       .macOS(.v13),
       .iOS(.v17),
    ],
    products: [
        .library(name: "OCIKit", targets: ["OCIKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.2.0"),
        .package(url: "https://github.com/PerfectlySoft/Perfect-INIParser.git", from: "3.0.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "OCIKit",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "_CryptoExtras", package: "swift-crypto"),
                .product(name: "INIParser", package: "Perfect-INIParser"),
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .testTarget(name: "OCIKItTests",
                   dependencies: ["OCIKit"])
    ]
)
