# AGENTS.md — Developer & AI Agent Guidelines for SwiftKit

Welcome to **SwiftKit**. This document serves as the single source of truth for AI agents and software engineers contributing to this repository. It defines architectural principles, repository structure, coding standards, concurrency guidelines, testing expectations, and contribution workflows.

---

## 1. Project Overview

- **Repository**: `SwiftKit`
- **Purpose**: A lightweight, production-grade native iOS utility SDK providing modular mobile architecture foundations with zero external third-party dependencies.
- **Target Platform**: iOS 15.0+ exclusively (for iOS mobile applications)
- **Swift Version**: Swift 5.9+ (Swift 5 language mode with modern concurrency readiness)
- **UI Frameworks**: Full support for both UIKit and SwiftUI client applications
- **Distribution**: Swift Package Manager (SPM)

---

## 2. Core Architectural Principles & Hard Constraints

Every agent and developer working on this codebase must adhere strictly to these principles:

### 2.1 Zero Third-Party Dependencies (Strict Rule)
- **Do NOT add external package dependencies** to `Package.swift` (no Alamofire, KeychainAccess, SnapKit, etc.).
- All modules **must rely exclusively on native Apple frameworks**:
  - `Foundation`
  - `UIKit`
  - `Security` (Keychain Services)
  - `OSLog` (`os.Logger`)
  - `Network` (`NWPathMonitor`)
  - `AVFoundation`
  - `Photos`
  - `CoreLocation`
  - `UserNotifications`

### 2.2 Exclusively Built for iOS Applications
SwiftKit is designed, architected, and maintained **exclusively for iOS mobile applications (iOS 15.0+)**.
- Tailored specifically for iOS mobile application lifecycles, UI paradigms (SwiftUI and UIKit), and device states.
- Leverages iOS platform capabilities including `UIDevice`, `UIScreen`, battery monitoring, app lifecycles, and system permissions.
- **Headless Host Runner Testing**: Local developer CLI workflows (`swift test`) and CI runners execute on macOS hosts. When interacting with iOS hardware or runtime singletons (`UIDevice`, `UIApplication`, `PHPhotoLibrary`, etc.), abstract them behind protocols or internal adapters so unit tests can execute headlessly via `swift test` on macOS build hosts without requiring a connected physical device or active simulator.

### 2.3 Single SPM Target Architecture
- The package exposes a single library and target named `SwiftKit` with root `Sources/SwiftKit`.
- All modules are organized under `Sources/SwiftKit/Modules/<ModuleName>/`.
- **Do not modify `Package.swift`** when creating or modifying modules. This prevents merge conflicts across concurrent feature branches and multi-agent workflows. Changes to `Package.swift` are reserved strictly for the **SDK Integrator** role.

### 2.4 Protocol-Driven & Decoupled Design
Every module is built around a public interface protocol:
- **`Public/`**: Contains public protocols, public enums, configuration types, and public extensions.
- **`Internal/`**: Contains internal concrete classes/actors implementing the public protocols.
- **`Models/`**: Contains internal or public data transfer objects, request/response models, or configuration objects.
- Client applications depend solely on protocols, never on concrete internal classes.

### 2.5 Centralized Facade & Dependency Injection
- `SwiftKit` is the public facade singleton (`SwiftKit.shared.<moduleName>`).
- All internal concrete implementations are instantiated and wired inside `SDKDependencyContainer`.
- Initialization follows a strict lifecycle: `SwiftKit.initialize(configuration:)` must be invoked prior to accessing `SwiftKit.shared`.

### 2.6 Modern Concurrency & Thread Safety
- Full conformance with Swift Concurrency: all public interfaces, data structures, and closures must be `Sendable` where appropriate.
- Protect mutable state using actors or thread-safe primitives (such as the included `ThreadSafeBox<Value>` or `NSLock`).
- Prefer `async/await` and `AsyncStream` over completion handlers for asynchronous flows.
- Avoid data races. Never use mutable global variables.

---

## 3. Directory Layout & Organization

Maintain the standard directory structure:

```text
SwiftKit/
├── .github/
│   └── pull_request_template.md        # Pull request template & checklist
├── .swiftlint.yml                      # SwiftLint rule configuration
├── Package.swift                       # SPM package manifest (Single target)
├── README.md                           # Public SDK documentation & quickstart
├── AGENTS.md                           # This operational guideline file
├── Sources/
│   └── SwiftKit/
│       ├── Core/                       # Core SDK initialization & DI container
│       │   ├── SDKEnvironment.swift    # Runtime environment (.development, .uat, .production)
│       │   ├── SDKError.swift          # Core SDK error definitions
│       │   ├── SwiftKitConfiguration.swift # Master configuration struct
│       │   ├── SDKDependencyContainer.swift # Internal DI container
│       │   └── SwiftKit.swift          # Public SDK facade singleton
│       ├── Modules/                    # Feature modules
│       │   ├── Logger/                 # Unified OSLog logging module
│       │   │   ├── Public/             # LoggerProtocol, LogLevel
│       │   │   ├── Internal/           # OSLogger
│       │   │   ├── Models/             # LogConfiguration
│       │   │   └── README.md           # Module documentation
│       │   ├── SecureStorage/          # Keychain storage module
│       │   ├── Networking/             # HTTP client module
│       │   ├── DeviceInfo/             # Device & app metrics module
│       │   ├── Connectivity/           # Network reachability module
│       │   ├── Session/                # User session state module
│       │   └── Permissions/            # System permissions module
│       └── Utilities/                  # Shared cross-cutting utilities
│           ├── Extensions/             # Foundation extensions (String, Data, etc.)
│           └── Helpers/                # DataMasker, ThreadSafeBox
└── Tests/
    └── SwiftKitTests/
        ├── Core/                       # Lifecycle & Configuration tests
        ├── IntegrationTests/           # End-to-end integration tests
        ├── LoggerTests/                # Logger module unit tests
        ├── SecureStorageTests/         # Keychain tests
        ├── NetworkingTests/            # Networking tests
        ├── DeviceInfoTests/            # DeviceInfo tests
        ├── ConnectivityTests/          # Connectivity tests
        ├── SessionTests/               # Session tests
        └── PermissionsTests/           # Permissions tests
```

---

## 4. Module Catalog & Responsibilities

| Module | Primary Interface | Apple Frameworks | Responsibility | Module Owner |
|---|---|---|---|---|
| **Core** | `SwiftKit`, `SwiftKitConfiguration` | `Foundation` | Centralized SDK initialization, DI wiring, environment control, and shared facade | SDK Integrator |
| **SecureStorage** | `SecureStorageProtocol` | `Security` | Generic Keychain CRUD operations (strings, data, codables), biometric access policies | Developer 1 |
| **Networking** | `NetworkClientProtocol` | `Foundation` (`URLSession`) | Async HTTP requests, endpoint builders, JSON encoding/decoding, error mapping | Developer 1 |
| **DeviceInfo** | `DeviceInfoProtocol` | `Foundation`, `UIKit` | Hardware model, OS version, app version, screen bounds, battery state | Developer 2 |
| **Connectivity** | `ConnectivityMonitorProtocol` | `Network` (`NWPathMonitor`) | Real-time network reachability, cellular/wifi detection, connection path updates | Developer 2 |
| **Session** | `SessionManagerProtocol` | `Foundation` | User session tokens, state tracking, expiry timestamps, session timeout handling | Developer 3 |
| **Logger** | `LoggerProtocol` | `OSLog` (`os.Logger`) | Structured diagnostic logging with automatic sensitive token/email redaction | Developer 3 |
| **Permissions** | `PermissionManagerProtocol` | `AVFoundation`, `Photos`, `CoreLocation`, `UserNotifications` | Permission status checking and authorization requests | Developer 3 |

---

## 5. Workflow for Adding or Updating a Module

When instructed to implement or update a module, execute the following steps in order:

### Step 1: Create Module Directory Structure
Under `Sources/SwiftKit/Modules/<ModuleName>/`, create:
1. `Public/`: The public protocol (e.g. `SecureStorageProtocol.swift`) and any public models/enums.
2. `Internal/`: Concrete implementation conforming to the protocol (e.g. `KeychainStorage.swift`).
3. `Models/`: Any internal/public configurations, options, or data types.
4. `README.md`: Document module ownership, Apple frameworks used, public API surface, and usage snippets.

### Step 2: Define the Public Protocol
- Ensure the protocol inherits from `Sendable` (or `AnyObject` + `Sendable` where required).
- Add full docstrings (`///`) to every method, property, and parameter.
- Use native Swift types (`Data`, `String`, `URL`, `Result`, `Codable`).
- Keep public APIs intuitive, minimal, and decoupled from underlying Apple implementation types where possible.

### Step 3: Implement the Concrete Class
- Mark the concrete class as `internal` and `final` (e.g. `internal final class KeychainStorage: SecureStorageProtocol, @unchecked Sendable`).
- Ensure thread safety: protect mutable state with `NSLock`, `ThreadSafeBox`, or use an `actor`.
- Redact sensitive data before logging using `DataMasker.mask(...)`.
- Abstract or mock iOS device-specific hardware/runtime singletons (`UIDevice`, `UIApplication`, `PHPhotoLibrary`) so unit tests run cleanly on host developer machines.

### Step 4: Wire into Dependency Container & Facade
1. Update `Sources/SwiftKit/Core/SwiftKitConfiguration.swift` if the module requires user configuration parameters.
2. Update `Sources/SwiftKit/Core/SDKDependencyContainer.swift`:
   - Add property: `internal let <moduleName>: <ModuleName>Protocol`
   - Instantiate inside `init(configuration:)` and inject into test initializers.
3. Update `Sources/SwiftKit/Core/SwiftKit.swift`:
   - Expose public property:
     ```swift
     public var <moduleName>: <ModuleName>Protocol {
         container.<moduleName>
     }
     ```

### Step 5: Implement Unit Tests
Under `Tests/SwiftKitTests/<ModuleName>Tests/`:
- Create test file (e.g. `<ModuleName>Tests.swift`).
- Add tests covering positive paths, edge cases, error conditions, and thread safety.
- For async APIs, write `async throws` test methods.
- For hardware/system dependencies (Keychain, `URLSession`, `NWPathMonitor`), create internal mock protocols or mock URL protocols to test in isolation without requiring physical devices.

### Step 6: Verify Build & Tests
Always run the test suite to ensure clean compilation and passing tests:
```bash
swift test
```

---

## 6. Coding Standards & Conventions

### 6.1 Access Modifiers
- `public`: Only items intended to be exported to consuming applications (Protocols, configuration structs, facade methods).
- `internal`: Concrete implementations, DI container, test helpers.
- `private` / `fileprivate`: Implementation details inside classes/structs.

### 6.2 Documentation
- All `public` protocols, classes, structs, enums, functions, and properties **must** have docstrings using `///`.
- Document parameters (`- Parameter ...`), return values (`- Returns: ...`), and thrown errors (`- Throws: ...`).

### 6.3 Concurrency & Memory Safety
- Strictly avoid retain cycles; use `[weak self]` in closures where necessary.
- Concurrency contracts: Types passed across concurrency domains must conform to `Sendable`.
- If using locks, prefer `defer { lock.unlock() }` immediately after `lock.lock()`.
- Utilize `ThreadSafeBox<Value>` for atomic mutations:
  ```swift
  let box = ThreadSafeBox<[String: Any]>([:])
  box.mutate { $0["key"] = "value" }
  ```

### 6.4 Data Security & Masking
- When outputting debug logs, network payloads, or diagnostic details, sensitive data (tokens, authorization headers, passwords, secrets, emails) **must be masked**.
- Call `DataMasker.mask(string)` whenever sensitive data might be logged or printed.

### 6.5 Error Handling
- Modules should declare specific, domain-focused error enums conforming to `Error, LocalizedError, Equatable, Sendable`.
- Provide meaningful `errorDescription` for diagnostics:
  ```swift
  public enum SecureStorageError: Error, LocalizedError, Equatable, Sendable {
      case itemNotFound(key: String)
      case writeFailed(status: OSStatus)
      
      public var errorDescription: String? {
          switch self {
          case .itemNotFound(let key):
              return "No item found in secure storage for key: \(key)"
          case .writeFailed(let status):
              return "Failed to write to secure storage with OSStatus code: \(status)"
          }
      }
  }
  ```

---

## 7. Testing Guidelines

### 7.1 Resetting Lifecycle Between Tests
`SwiftKit` is a singleton. In test cases that initialize the SDK, **always reset state** in `setUp()` and `tearDown()`:
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

### 7.2 Testing via Dependency Injection
When testing components that depend on other modules:
- Use `SDKDependencyContainer(configuration: ..., <module>: mockModule)` to inject mock implementations.
- Use `SwiftKit.initializeForTesting(container:)` to test facade wiring with mocks.

### 7.3 Testing Asynchronous Code
Use native Swift async testing:
```swift
func testAsyncOperation() async throws {
    let result = try await service.fetchData()
    XCTAssertEqual(result.status, "ok")
}
```

---

## 8. Common Developer & Agent Commands

Run these terminal commands from the workspace root:

| Command | Purpose |
|---|---|
| `swift build` | Compiles the entire SDK target |
| `swift test` | Runs all unit and integration tests |
| `swift test --filter <TestSuite>` | Runs a specific test suite (e.g. `swift test --filter LoggerTests`) |
| `swift test --filter <TestSuite>/<testCase>` | Runs an individual test case |
| `swift package clean` | Cleans temporary build artifacts |

---

## 9. Pre-PR & Task Completion Checklist

Before finalizing any task or PR, verify every item below:

- [ ] **Zero External Dependencies**: Verified that `Package.swift` has not introduced any third-party dependencies.
- [ ] **iOS-Only Target & Architecture**: Verified implementation is tailored exclusively for iOS applications (iOS 15.0+).
- [ ] **Single SPM Target Intact**: No extra targets or unnecessary modifications were made to `Package.swift`.
- [ ] **Architecture Conformity**:
  - Public interface is exposed via a protocol under `Public/`.
  - Concrete class is marked `internal` under `Internal/`.
  - Wires into `SDKDependencyContainer` and `SwiftKit` facade.
- [ ] **Docstrings**: All public APIs contain clear triple-slash (`///`) docstrings.
- [ ] **Tests Added & Passing**: Unit tests added in `Tests/SwiftKitTests/<ModuleName>Tests/` and `swift test` passes with zero failures.
- [ ] **Module README**: Created or updated `Sources/SwiftKit/Modules/<ModuleName>/README.md`.
- [ ] **Data Redaction**: Sensitive information is sanitized through `DataMasker` when logged.
- [ ] **Thread Safety & Sendable**: Concurrency models are validated and race-condition free.
