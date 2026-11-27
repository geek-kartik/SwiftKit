# AGENTS.md — SwiftKit Contributor Guide

SwiftKit is a SwiftPM utility SDK for iOS apps. This file is the contributor rulebook: it defines architecture, coding, testing, and documentation expectations. User-facing documentation lives in [README.md](README.md), the module READMEs, and [SampleApp/README.md](SampleApp/README.md).

---

## 1. Project facts

- **Purpose**: lightweight, production-grade mobile architecture foundations with zero third-party dependencies.
- **Package**: Swift tools 5.9, Swift 5 language mode, one library target (`SwiftKit`) plus one test target (`SwiftKitTests`).
- **Platforms**: `Package.swift` declares iOS 15+ and macOS 12+. APIs are designed for iOS apps, but the SDK source uses no UIKit and must keep building on the macOS host used by `swift test`.
- **Client UI**: apps may use SwiftUI or UIKit; the SDK itself exposes no UI framework types.
- **Frameworks in use**: `Foundation`, `Security`, `OSLog`, `Network`, and `Darwin`. Do not introduce another framework or dependency without SDK Integrator approval.

---

## 2. Hard constraints

### 2.1 Zero third-party dependencies
- Never add external packages to `Package.swift` (no Alamofire, KeychainAccess, SnapKit, etc.).
- Use native Apple APIs only.

### 2.2 Single SPM target
- All modules live under `Sources/SwiftKit/Modules/<ModuleName>/` in the single `SwiftKit` target.
- **Do not modify `Package.swift`** when adding or updating modules. Only the SDK Integrator changes the manifest.

### 2.3 iOS-first, host-testable
- Keep SDK code free of `UIKit`, `UIDevice`, `UIApplication`, `UIScreen`, and battery APIs.
- Abstract system effects behind internal protocols or factories so unit tests run headlessly on macOS: `KeychainClient` for Keychain, `HTTPTransport` / `URLProtocol` for networking, `NetworkPathMonitorEngineFactory` for `NWPathMonitor`, and injected `Bundle` / `ProcessInfo` values for device metadata.

### 2.4 Protocol-driven layout
Every module uses the same structure:

| Directory | Contents |
|---|---|
| `Public/` | Public protocols, enums, errors, and configuration types |
| `Internal/` | `internal final` implementations and injectable system adapters |
| `Models/` | Data and configuration value types |
| `README.md` | Module-level usage documentation |

Consumers depend on public protocols, never on `Internal/` types.

### 2.5 Facade and dependency injection
- `SwiftKit` (`Sources/SwiftKit/Core/SwiftKit.swift`) is the facade: `SwiftKit.shared.<module>`.
- `SDKDependencyContainer` creates concrete implementations and supports a test initializer with injectable mocks.
- `SwiftKit.initialize(configuration:)` validates configuration and must be called before `SwiftKit.shared`; otherwise `shared` traps.

### 2.6 Concurrency and thread safety
- Public types and closures passed across concurrency domains must be `Sendable` where appropriate.
- Protect mutable state with `NSLock` or `ThreadSafeBox<Value>`; use an actor when ownership is clearer.
- Prefer `async/await` for asynchronous APIs. Use streams only when a continuous event flow is needed.
- Use `[weak self]` in escaping closures owned by long-lived objects; never use mutable global state.

---

## 3. Repository layout

```text
SwiftKit/
├── Package.swift                    # Single SDK target; no third-party dependencies
├── README.md                        # SDK overview, install, quick start, module links
├── AGENTS.md                        # This guide
├── .swiftlint.yml                   # Optional lint configuration
├── Sources/SwiftKit/
│   ├── Core/                        # SwiftKit, SwiftKitConfiguration, SDKDependencyContainer,
│   │                                # SDKEnvironment, SDKError
│   ├── Modules/
│   │   ├── Logger/                  # LoggerProtocol, LogLevel, OSLogger
│   │   ├── SecureStorage/           # SecureStorageProtocol, KeychainStorage
│   │   ├── Networking/              # NetworkClientProtocol, URLSessionNetworkClient
│   │   ├── DeviceInfo/              # DeviceInfoProtocol, SystemDeviceInfo
│   │   ├── Connectivity/            # ConnectivityMonitorProtocol, NetworkConnectivityMonitor
│   │   └── Session/                 # SessionManagerProtocol, SessionManager
│   └── Utilities/
│       ├── Extensions/              # String and Data helpers
│       └── Helpers/                 # DataMasker, ThreadSafeBox, JSONTextFormatter
├── Tests/SwiftKitTests/
│   ├── Core/ IntegrationTests/
│   ├── LoggerTests/ SecureStorageTests/ NetworkingTests/
│   └── DeviceInfoTests/ ConnectivityTests/ SessionTests/
└── SampleApp/
    ├── project.yml                  # XcodeGen spec; local SwiftKit package (`path: ..`)
    ├── SampleApp.xcodeproj
    ├── README.md
    └── Sources/ Tests/              # SwiftUI demo + XCTest mocks and URLProtocol stub
```

---

## 4. Module catalog

| Module | Primary interface | Frameworks | Responsibility |
|---|---|---|---|
| Core | `SwiftKit`, `SwiftKitConfiguration` | `Foundation` | Initialization, validation, DI wiring, facade |
| Logger | `LoggerProtocol` | `OSLog` | Level-filtered diagnostics with masking |
| SecureStorage | `SecureStorageProtocol` | `Security` | Keychain CRUD for data, strings, and `Codable` values |
| Networking | `NetworkClientProtocol` | `Foundation` | Async HTTP, URL/header handling, JSON mapping, typed errors |
| DeviceInfo | `DeviceInfoProtocol` | `Foundation`, `Darwin` | Device, OS, and app metadata; version comparisons |
| Connectivity | `ConnectivityMonitorProtocol` | `Network` | Network-path status and change observers |
| Session | `SessionManagerProtocol` | `Foundation` | Persisted session state, expiry, refresh, observers |

## 4.1 Current implementation boundaries

Do not assume these features exist; they are not in `Sources/`:

- Network inspector UI/overlay, console request logging, automatic 401 refresh/retry. `tokenProvider`, `onError`, and `onAuthenticationFailure` are wired; `NetworkConfiguration.refreshToken`, `logErrorDetails`, and `LogVerbosity` are not.
- Biometric Keychain policies, keychain access groups, UIKit/screen/battery APIs, cellular/Wi-Fi interface detection, and idle session timeouts.

Document and build against what is implemented. Extend these boundaries deliberately rather than describing planned work as shipped.

---

## 5. Workflow for adding or updating a module

1. **Structure**: create `Public/`, `Internal/`, `Models/`, and `README.md` under `Sources/SwiftKit/Modules/<ModuleName>/`.
2. **Public contract**: define a `Sendable` protocol with complete `///` docstrings. Use native types (`Data`, `String`, `URL`, `Codable`) and keep the API minimal.
3. **Implementation**: use `internal final class ...: <Module>Protocol, Sendable`. Use `@unchecked Sendable` only when compiler-checked conformance is impossible. Inject system adapters for headless tests.
4. **Wiring**:
   - Add configuration with safe defaults in `SwiftKitConfiguration.swift`.
   - Add a stored property and instantiation in both initializers of `SDKDependencyContainer.swift`.
   - Expose the protocol through a facade property in `SwiftKit.swift`.
   - Update the manifest only if you are the SDK Integrator.
5. **Tests**: add `Tests/SwiftKitTests/<ModuleName>Tests/` covering success paths, edge cases, errors, and concurrency. Use `async throws` tests for async APIs and mocks for system dependencies.
6. **Verify**: run `swift build && swift test`. If the sample app changed, also run the `xcodebuild` commands in section 8.

---

## 6. Coding standards

### 6.1 Access modifiers
- `public`: only protocols, public value types, and facade APIs consumed by apps.
- `internal`: concrete implementations, DI container, and test helpers.
- `private` / `fileprivate`: implementation details.

### 6.2 Documentation
- Every public declaration needs `///` docstrings, including parameters, returns, and thrown errors.
- Keep module READMEs in sync with public API changes; do not duplicate the root README's installation instructions.

### 6.3 Concurrency and memory safety
- Use `defer { lock.unlock() }` immediately after `lock.lock()`.
- Prefer immutable stored state; mutate through `ThreadSafeBox` or an actor:
  ```swift
  let box = ThreadSafeBox<[String: Any]>([:])
  box.mutate { $0["key"] = "value" }
  ```

### 6.4 Data security
- Never log raw tokens, authorization headers, passwords, emails, or request/response bodies. Pass diagnostic text through `DataMasker.mask(_:)` first.
- `NetworkTransaction` stores raw bodies; callers must mask them before display or logging. Its cURL helpers redact credential headers by default.

### 6.5 Errors
- Declare domain errors as `Error, LocalizedError, Equatable, Sendable` with meaningful `errorDescription`.
- Keep keys, tokens, and raw values out of error messages used for diagnostics.

---

## 7. Testing guidelines

### 7.1 Singleton lifecycle
Tests use `@testable import SwiftKit` to access internal test hooks. Reset the singleton in tests that initialize the SDK:

```swift
override func setUp() {
    super.setUp()
    SwiftKit.resetForTesting()
}

override func tearDown() {
    SwiftKit.resetForTesting()
    super.tearDown()
}
```

### 7.2 Injecting mocks
Use the test initializer with the exact labels of `SDKDependencyContainer`:

```swift
let container = SDKDependencyContainer(
    configuration: configuration,
    logger: MockLogger(),
    secureStorage: MockSecureStorage(),
    networkClient: MockNetworkClient()
)
SwiftKit.initializeForTesting(container: container)
```

`connectivityMonitor`, `deviceInfo`, `sessionManager`, and `sessionTokenRefreshHandler` are also injectable; omitted modules get production implementations.

### 7.3 Async tests
```swift
func testAsyncOperation() async throws {
    let result = try await service.fetchData()
    XCTAssertEqual(result.status, "ok")
}
```

---

## 8. Commands

From the repository root:

```bash
swift build
swift test
swift test --filter LoggerTests
```

Sample app (Xcode + iOS simulator required):

```bash
xcodebuild build -project SampleApp/SampleApp.xcodeproj \
  -scheme SampleApp -destination "generic/platform=iOS Simulator"

xcodebuild test -project SampleApp/SampleApp.xcodeproj \
  -scheme SampleApp -destination "platform=iOS Simulator,name=iPhone 17"
```

Use an installed simulator name in the test command. The app target is manually ad-hoc signed for simulator builds (`CODE_SIGN_STYLE=Manual`, `CODE_SIGN_IDENTITY="-"`, no team/profile) so it runs on any Mac without provisioning. Keychain behavior on unsigned/entitlement-less simulator builds can vary by host; if Keychain access fails, use a signed build with an appropriate entitlement. Run `xcodegen generate` from `SampleApp/` only after changing `project.yml`. `swift test` does not build the sample app.

---

## 9. Documentation levels

| File | Scope |
|---|---|
| `README.md` | Evaluation, installation, quick start, module links, build/test, sample app |
| `Sources/SwiftKit/Modules/<Name>/README.md` | Purpose, public API, configuration, errors, limits, module-specific examples |
| `SampleApp/README.md` | Setup, offline mock backend, demonstrated flows, build/run commands |

Update every level affected by an API change; keep examples copy-pasteable and verified against the source.

---

## 10. Pre-PR checklist

- [ ] No third-party dependencies; `Package.swift` unchanged unless you are the SDK Integrator.
- [ ] Builds with `swift build`; `swift test` passes.
- [ ] Public API is protocol-driven, documented, `Sendable` where appropriate, and wired through the container/facade.
- [ ] Mutable state is lock/actor protected; no data races.
- [ ] Sensitive values are masked before logging or display.
- [ ] Tests cover new behavior, including errors and concurrency.
- [ ] Affected module README, root README snippets, and `SampleApp/README.md` are updated.
- [ ] No documentation claims unsupported features from section 4.1.
