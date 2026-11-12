# SwiftKit

A lightweight, production-grade native iOS utility SDK designed to provide common mobile architecture foundations through independent, decoupled, and testable modules with zero external third-party dependencies.

---

## Supported Modules & Technologies

| Module | Purpose | Native Apple Framework | Primary Interface |
|---|---|---|---|
| **Secure Storage** | Keychain-based credential & token storage | `Security` | `SecureStorageProtocol` |
| **Networking** | Asynchronous HTTP client with JSON mapping | `Foundation` (`URLSession`) | `NetworkClientProtocol` |
| **Device Info** | Safe hardware, OS, and app version metrics | `Foundation`, `UIKit` | `DeviceInfoProtocol` |
| **Connectivity** | Real-time network reachability monitoring | `Network` (`NWPathMonitor`) | `ConnectivityMonitorProtocol` |
| **Session** | User session state and expiration checking | `Foundation` | `SessionManagerProtocol` |
| **Logger** | Unified logging with automatic data masking | `OSLog` (`os.Logger`) | `LoggerProtocol` |
| **Permissions** | Camera, Photos, Location, Notification access | `AVFoundation`, `Photos`, `CoreLocation`, `UserNotifications` | `PermissionManagerProtocol` |
| **Core** | Centralized SDK initialization & DI container | `Foundation` | `SwiftKit` |

---

## Architecture Highlights

- **Single SPM Target**: `SwiftKit` contains all 7 independent module folders to avoid concurrent `Package.swift` merge conflicts.
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
    baseURL: URL(string: "https://api.example.com")!,
    requestTimeout: 30.0,
    keychainService: "com.example.app.storage",
    isLoggingEnabled: true
)

try SwiftKit.initialize(configuration: configuration)
```

### 2. Access Utilities via Shared Facade

```swift
// Logging with automatic sensitive token redaction
SwiftKit.shared.logger.info("Application started successfully.")

// Secure Keychain Storage
try SwiftKit.shared.secureStorage.setString("jwt_token_here", forKey: "authToken")

// Asynchronous Networking
struct User: Decodable { let id: String; let name: String }
let request = APIRequest(path: "/v1/users/me", method: .get)
let user: User = try await SwiftKit.shared.networking.send(request)

// Device Information
let device = SwiftKit.shared.deviceInfo
print("Device: \(device.deviceModel), Version: \(device.appVersion)")

// Connectivity Monitoring
let connectivity = SwiftKit.shared.connectivity
connectivity.startMonitoring()
print("Is Online: \(connectivity.isConnected)")

// Permissions
let cameraStatus = await SwiftKit.shared.permissions.status(for: .camera)
```

---