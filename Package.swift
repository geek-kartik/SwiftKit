// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftKit",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        // The single public SDK library product exported to consumers
        .library(
            name: "SwiftKit",
            targets: ["SwiftKit"]
        )
    ],
    targets: [
        .target(
            name: "SwiftKit",
            dependencies: [],
            path: "Sources/SwiftKit",
            exclude: [
                "Modules/Logger/README.md",
                "Modules/SecureStorage/README.md",
                "Modules/DeviceInfo/README.md",
                "Modules/Connectivity/README.md",
                "Modules/Networking/README.md",
                "Modules/Session/README.md"
            ]
        ),
        // Comprehensive test suite
        .testTarget(
            name: "SwiftKitTests",
            dependencies: ["SwiftKit"],
            path: "Tests/SwiftKitTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
