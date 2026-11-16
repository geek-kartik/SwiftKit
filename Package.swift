// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftKit",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        // The single public SDK library product exported to consumers
        .library(
            name: "SwiftKit",
            targets: ["SwiftKit"]
        )
    ],
    dependencies: [
        // No third-party dependencies. SwiftKit relies solely on native Apple frameworks.
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
                "Modules/Connectivity/README.md"
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
