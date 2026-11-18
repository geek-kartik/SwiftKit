# SwiftKit

A native iOS utility SDK which provides common mobile architecture foundations through independent, decoupled, and testable modules with zero external third-party dependencies.

---

## Supported Modules & Technologies

| Module | Status | Purpose | Native Apple Framework | Primary Interface |
|---|---|---|---|---|
| **Core** | Implemented | Centralized SDK initialization & DI container | `Foundation` | `SwiftKit` |
| **Logger** | Implemented | Unified logging with automatic data masking | `OSLog` (`os.Logger`) | `LoggerProtocol` |
| **Secure Storage** | Implemented | Keychain-based credential & token storage | `Security` | `SecureStorageProtocol` |
| **Networking** | Implemented | Asynchronous HTTP client with JSON mapping and a session inspector | `Foundation` (`URLSession`), `SwiftUI` (inspector) | `NetworkClientProtocol`, `NetworkInspectorProtocol` |
| **Device Info** | Implemented | Device model, app/OS versions, and build environment | `Foundation` | `DeviceInfoProtocol` |
| **Connectivity** | Implemented | System network-path monitoring and change notifications | `Network` (`NWPathMonitor`) | `ConnectivityMonitorProtocol` |
| **Session** | Planned | User session state and expiration checking | `Foundation` | `SessionManagerProtocol` |

---

## Architecture Highlights

- **Single SPM Target**: `SwiftKit` contains all module folders in one target to avoid concurrent `Package.swift` merge conflicts.
- **Protocol-Driven**: Clean separation between `Public/` contracts, `Internal/` implementations, and `Models/`.
- **Modern Concurrency**: First-class support for `async/await` and `AsyncStream`.
- **Global Error Hooks**: Centralized `onError` and `onAuthenticationFailure` callbacks for flows such as automatic sign-out on `401`.
- **Optional In-App Debugging**: A disabled-by-default session inspector with copy-as-cURL, plus a draggable floating trigger that opens it as a global sheet.
- **Zero Third-Party Dependencies**: Pure native Apple SDK implementation.
- **UI Agnostic**: Seamlessly integrates into both SwiftUI and UIKit client applications.

---

## Example App

[`Examples/BankingDemo`](Examples/BankingDemo/README.md) is a complete SwiftUI banking app
built on the SDK. It exercises every HTTP verb, JSON encoding/decoding, bearer auth,
Keychain-backed token storage, and the full `NetworkError` surface — against an in-app
localhost server, so it runs offline with no backend. A draggable floating button opens the
SDK's session log as a global sheet with headers, bodies, and copy-as-cURL.

```bash
open Examples/BankingDemo/BankingDemo.xcodeproj
```

---

## Integration via Swift Package Manager

Add SwiftKit to your `Package.swift` manifest or via Xcode Package Dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/geek-kartik/SwiftKit.git", branch: "main")
]
```

Link `SwiftKit` to your target:
```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "SwiftKit", package: "SwiftKit")
    ]
)
```

---

## Quick Start & Usage

### 1. Initialize the SDK
Initialize early during application startup:

```swift
import SwiftKit

let configuration = SwiftKitConfiguration(
    environment: .development,
    keychainService: "com.example.app.storage",
    keychainAccessibility: .afterFirstUnlockThisDeviceOnly,
    isLoggingEnabled: true
)

try SwiftKit.initialize(configuration: configuration)
```

### 2. Access Utilities via Shared Facade

```swift
// Logging with automatic sensitive data redaction
SwiftKit.shared.logger.info("Application started successfully.")

// Secure Keychain Storage
try SwiftKit.shared.secureStorage.setString("jwt_token_here", forKey: "authToken")
let token = try SwiftKit.shared.secureStorage.string(forKey: "authToken")

// Remove a stored value when it is no longer needed
try SwiftKit.shared.secureStorage.remove(forKey: "authToken")

// Device model, version, and build environment information
let deviceInfo = SwiftKit.shared.deviceInfo
let model = deviceInfo.deviceModel
let osVersion = deviceInfo.osVersion
let appVersion = deviceInfo.appVersion
let buildNumber = deviceInfo.buildNumber
let bundleIdentifier = deviceInfo.bundleIdentifier
let appName = deviceInfo.appName
let isSimulator = deviceInfo.isSimulator
let isDebugBuild = deviceInfo.isDebugBuild

// Force-update and feature-gating helpers
if deviceInfo.isUpdateRequired(minimumVersion: "2.5.0") {
    // Prompt the user to update.
}

// Connectivity Monitoring
let connectivity = SwiftKit.shared.connectivity
connectivity.start()

// Banking API requests with JSON encoding, decoding, and standardized errors
let request = try NetworkRequest(
    path: "/v1/accounts/acc_1",
    headers: ["Authorization": "Bearer \(accessToken)"]
)
let account: Account = try await SwiftKit.shared.networkClient.send(request, as: Account.self)
```

### 3. Module Documentation

- [Logger Module](Sources/SwiftKit/Modules/Logger/README.md)
- [Secure Storage Module](Sources/SwiftKit/Modules/SecureStorage/README.md)
- [Device Info Module](Sources/SwiftKit/Modules/DeviceInfo/README.md)
- [Connectivity Module](Sources/SwiftKit/Modules/Connectivity/README.md)
- [Networking Module](Sources/SwiftKit/Modules/Networking/README.md)

Session is a planned module and will be documented when implemented.

---
