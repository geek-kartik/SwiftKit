# SwiftKit Sample Application

A production-quality iOS SwiftUI sample application demonstrating the integration and real-world consumption of the **SwiftKit SDK** using its public APIs.

---

## 1. Demonstrated Modules & Capabilities

| Module | Public Interface | Demonstrated Features |
|---|---|---|
| **Secure Storage** | `SecureStorageProtocol` | • Keychain-backed string persistence (`setString`, `string`)<br>• `Codable` struct round-trip persistence (`setCodable`, `codable`)<br>• Raw binary `Data` storage (`setData`, `data`)<br>• Key existence verification (`contains`)<br>• Single key deletion (`remove`) & batch wiping (`removeAll`)<br>• Error handling for missing keys (`itemNotFound`), invalid keys, and storage failures |
| **Device Information** | `DeviceInfoProtocol` | • Hardware model identifier (`deviceModel`)<br>• OS version string (`osVersion`)<br>• App marketing version (`appVersion`) and build number (`buildNumber`)<br>• Host application display name (`appName`) and bundle identifier (`bundleIdentifier`)<br>• Simulator detection flag (`isSimulator`) and debug build flag (`isDebugBuild`)<br>• Dynamic version evaluation tool (`isAppVersionAtLeast`, `isUpdateRequired`, `isOSVersionAtLeast`) |
| **Connectivity Monitoring** | `ConnectivityMonitorProtocol` | • Live network path status (`currentStatus`: `.connected`, `.disconnected`, `.unknown`)<br>• Monitoring lifecycle management (`start()`, `stop()`, `isMonitoring`)<br>• Observer registration and teardown (`addObserver`, `removeObserver`, `ConnectivityObservationToken`)<br>• Thread-safe event dispatch to MainActor UI with transition history timeline |
| **Logging** | `LoggerProtocol` | • Structured logging across all severity levels: `debug`, `info`, `warning`, `error`, `none`<br>• Origin source context tracking (file, function, line)<br>• Dynamic log dispatch with level picker<br>• Automatic sensitive token and email redaction demonstration via `DataMasker` |
| **Session Management** | `SessionManagerProtocol` | • Session creation, restoration, validation, and logout<br>• Synchronous refresh and async refresh via `SessionTokenRefreshHandler`<br>• Observer events for authenticated, refreshed, expired, logged out, and unauthorized transitions<br>• Masked bearer-token display using `DataMasker`<br>• Simulated HTTP 401 handling through `handleUnauthorized()` |
| **Networking** | `NetworkClientProtocol` | • GET/POST/PUT/PATCH/DELETE against an offline `URLProtocol` stub<br>• JSON request encoding and typed response decoding<br>• Automatic bearer header injection through `NetworkConfiguration.tokenProvider`<br>• `NetworkError` handling for 401, 404, 500, and decoding failures<br>• `onError` / `onAuthenticationFailure` callback events<br>• App-level `401 → session.refreshSession() → retry once` flow |
| **Core Architecture** | `SwiftKit`, `SwiftKitConfiguration` | • Centralized lifecycle initialization (`SwiftKit.initialize(configuration:)`)<br>• Validated configuration with environment settings (`.development`)<br>• Network configuration and session refresh-handler injection<br>• Public facade singleton access (`SwiftKit.shared`) |

---

## 2. Architecture & Design Patterns

The sample application follows clean MVVM + Service Layer architecture:

- **App Initialization (`App/SampleApp.swift`)**:
  Initializes `SwiftKit` on startup using `SwiftKitConfiguration` with strict parameter validation and error handling.
- **Service Layer (`Services/SDKService.swift`)**:
  Implements `SDKServiceProtocol` exposing public SDK facade references (`SwiftKit.shared.*`) to enable seamless dependency injection and testability.
- **ViewModels (`ViewModels/`)**:
  - `SecureStorageViewModel`: `@MainActor` class managing Keychain CRUD, state feedback, and `SampleSessionProfile` serialization.
  - `DeviceInfoViewModel`: `@MainActor` class managing metadata loading and real-time version comparisons.
  - `ConnectivityViewModel`: `@MainActor` class managing network path observation, token lifecycle, and transition events.
  - `LoggingViewModel`: `@MainActor` class managing log triggers, level selection, and data masking demonstrations.
  - `SessionViewModel`: `@MainActor` class managing session lifecycle actions, observer events, and 401 simulation.
  - `NetworkingViewModel`: `@MainActor` class managing HTTP verbs, JSON mapping, callback events, and refresh-after-401 retries.
- **Offline Backend (`Services/SampleBackend.swift`)**:
  - `SampleBackend`: actor-backed deterministic stub with token-expiry simulation.
  - `SampleURLProtocol`: intercepts `https://sample.swiftkit.test` requests so every demo runs without a backend.
- **Views (`Views/`)**:
  - `DashboardView`: Comprehensive status overview, live metrics, and direct navigation links to each module.
  - `SecureStorageView`: Interactive Keychain CRUD console.
  - `DeviceInfoView`: Structured system metrics and version gating testing tool.
  - `ConnectivityView`: Real-time path status badge, controls, and event log.
  - `LoggingView`: Predefined level triggers, custom dispatcher, and in-app log console.
  - `SessionView`: Session state card, lifecycle controls, masked token display, and observer timeline.
  - `NetworkingView`: Request builder, quick scenarios, decoded response, callback feed, and call history.

---

## 3. Building and Running

### Prerequisites
- macOS 14.0+
- Xcode 15.0+ (iOS 15.0+ Simulator SDK)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

### Project Generation
From the `SampleApp` directory:
```bash
xcodegen generate
```

### Build with xcodebuild
```bash
xcodebuild build -project SampleApp/SampleApp.xcodeproj -scheme SampleApp -destination "generic/platform=iOS Simulator" CODE_SIGNING_ALLOWED=NO
```

### Run Unit Tests
```bash
xcodebuild test -project SampleApp/SampleApp.xcodeproj -scheme SampleApp -destination "platform=iOS Simulator,name=iPhone 17" CODE_SIGNING_ALLOWED=NO
```
