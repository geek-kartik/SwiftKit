# SwiftKit

A native iOS utility SDK which provides common mobile architecture foundations through independent, decoupled, and testable modules with zero external third-party dependencies.

---

## Supported Modules & Technologies

| Module | Status | Purpose | Native Apple Framework | Primary Interface |
|---|---|---|---|---|
| **Core** | Implemented | Centralized SDK initialization & DI container | `Foundation` | `SwiftKit` |
| **Logger** | Implemented | Unified logging with automatic data masking | `OSLog` (`os.Logger`) | `LoggerProtocol` |
| **Secure Storage** | Implemented | Keychain-based credential & token storage | `Security` | `SecureStorageProtocol` |
| **Networking** | Planned | Asynchronous HTTP client with JSON mapping | `Foundation` (`URLSession`) | `NetworkClientProtocol` |
| **Device Info** | Implemented | Safe hardware model and app/OS version metrics | `Foundation` | `DeviceInfoProtocol` |
| **Connectivity** | Planned | Real-time network reachability monitoring | `Network` (`NWPathMonitor`) | `ConnectivityMonitorProtocol` |
| **Session** | Planned | User session state and expiration checking | `Foundation` | `SessionManagerProtocol` |

---

## Architecture Highlights

- **Single SPM Target**: `SwiftKit` contains all module folders in one target to avoid concurrent `Package.swift` merge conflicts.
- **Protocol-Driven**: Clean separation between `Public/` contracts, `Internal/` implementations, and `Models/`.
- **Modern Concurrency**: First-class support for `async/await` and `AsyncStream`.
- **Zero Third-Party Dependencies**: Pure native Apple SDK implementation.
- **UI Agnostic**: Seamlessly integrates into both SwiftUI and UIKit client applications.

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

// Device model and version information
let deviceInfo = SwiftKit.shared.deviceInfo
let model = deviceInfo.deviceModel
let osVersion = deviceInfo.osVersion
let appVersion = deviceInfo.appVersion
let buildNumber = deviceInfo.buildNumber
```

### 3. Module Documentation

- [Logger Module](Sources/SwiftKit/Modules/Logger/README.md)
- [Secure Storage Module](Sources/SwiftKit/Modules/SecureStorage/README.md)

Networking, Connectivity, and Session are planned modules and will be documented when implemented.

---
