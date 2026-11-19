# SwiftKit

A native iOS utility SDK that provides common mobile architecture foundations through all independent, protocol-driven modules. It has zero third-party dependencies and works in both SwiftUI and UIKit apps.

## Requirements

| Requirement | Version |
|---|---|
| iOS | 15.0+ |
| Swift | 5.9+ (Swift 5 language mode) |
| Xcode | 15.0+ |
| Dependencies | None; Apple frameworks only |

`Package.swift` also declares macOS 12.0+ so the package and its tests can be built on a Mac host. Implementation uses `Foundation`, `Security`, `Network`, and `OSLog`; no UIKit APIs are used.

## Modules

| Module | Interface | What it provides |
|---|---|---|
| [Logger](Sources/SwiftKit/Modules/Logger/README.md) | `LoggerProtocol` | `OSLog`-backed logging with masking of sensitive values |
| [Secure Storage](Sources/SwiftKit/Modules/SecureStorage/README.md) | `SecureStorageProtocol` | Keychain CRUD for strings, data, and `Codable` values |
| [Networking](Sources/SwiftKit/Modules/Networking/README.md) | `NetworkClientProtocol` | Async HTTP requests, JSON mapping, typed errors |
| [Device Info](Sources/SwiftKit/Modules/DeviceInfo/README.md) | `DeviceInfoProtocol` | Device, OS, and app metadata with version helpers |
| [Connectivity](Sources/SwiftKit/Modules/Connectivity/README.md) | `ConnectivityMonitorProtocol` | `NWPathMonitor`-based status and change callbacks |
| [Session](Sources/SwiftKit/Modules/Session/README.md) | `SessionManagerProtocol` | Persisted session state, expiry, refresh, and observers |

Core (`Sources/SwiftKit/Core/`) wires the modules in `SDKDependencyContainer` and exposes them through `SwiftKit.shared`. Each module folder follows `Public/` (protocols and public types), `Internal/` (concrete implementations), and `Models/` (configuration and data types).

## Installation

Add the package in Xcode (**File → Add Package Dependencies…**) using `https://github.com/geek-kartik/SwiftKit`, or add it to `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/geek-kartik/SwiftKit.git", branch: "main")
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [.product(name: "SwiftKit", package: "SwiftKit")]
    )
]
```

## Quick start

Initialize once, early in app startup. `SwiftKit.initialize(configuration:)` validates the configuration and throws `SDKError.invalidConfiguration` or `SDKError.alreadyInitialized`; accessing `SwiftKit.shared` before a successful initialize traps.

```swift
import SwiftKit

let configuration = SwiftKitConfiguration(
    subsystem: "com.example.app",
    category: "App",
    keychainService: "com.example.app.storage",
    network: NetworkConfiguration(baseURL: URL(string: "https://api.example.com")!)
)

try SwiftKit.initialize(configuration: configuration)

SwiftKit.shared.logger.info("Application started")

try SwiftKit.shared.secureStorage.setString("token", forKey: "authToken")
let token = try SwiftKit.shared.secureStorage.string(forKey: "authToken")

SwiftKit.shared.connectivity.start()

let request = try NetworkRequest(path: "/v1/accounts/1")
let response = try await SwiftKit.shared.networkClient.send(request)
```

Each module README has complete examples, including session creation and typed request decoding.

### Error and authentication callbacks

`NetworkConfiguration.onError` and `.onAuthenticationFailure` receive a `NetworkTransaction` for failed requests. They report auth failures (`401`/`403`) but do not sign the user out or retry automatically; handle that in your app. The [sample app](SampleApp/README.md) shows a `401 → refresh → retry once` flow.

## Sample app

[SampleApp](SampleApp/README.md) is a SwiftUI app that demonstrates all modules against an offline `URLProtocol` stub. Run it with:

```bash
open SampleApp/SampleApp.xcodeproj
```

## Build and test

From the repository root:

```bash
swift build
swift test
swift test --filter LoggerTests
```

`swift test` builds and runs on the Mac host; no simulator or device is required.

## Contributing

Follow the architecture, coding, and test conventions in [AGENTS.md](AGENTS.md). Keep the single SPM target and zero-dependency rules intact.
