# Secure Storage Module

## Purpose & Scope
Provides Keychain-backed storage for sensitive values such as access tokens, refresh tokens, credentials, and small Codable payloads. The module exposes a protocol-driven API so client applications never depend on the concrete Keychain implementation.

## Apple Frameworks
- `Security` (`SecItemAdd`, `SecItemCopyMatching`, `SecItemUpdate`, `SecItemDelete`)
- `Foundation`

## Module Owner
Developer 1

## Architecture
- `Public/SecureStorageProtocol.swift`: Public storage contract plus String and `Codable` conveniences.
- `Public/SecureStorageAccessibility.swift`: Public Keychain accessibility policies.
- `Public/SecureStorageError.swift`: Typed, `Sendable` storage errors.
- `Internal/KeychainStorage.swift`: Concrete `SecureStorageProtocol` implementation. Uses an injected `KeychainClient` and `LoggerProtocol`.
- `Internal/KeychainClient.swift`: Internal Keychain abstraction used for headless testing.
- `Internal/SystemKeychainClient.swift`: `Security.framework` implementation of `KeychainClient`.

## Configuration
`SwiftKitConfiguration` exposes the following SecureStorage options:

| Option | Default | Description |
|---|---|---|
| `keychainService` | Host bundle identifier or `"com.swiftkit.sdk"` | Keychain service namespace used to scope stored values. |
| `keychainAccessibility` | `.afterFirstUnlockThisDeviceOnly` | Access policy applied to newly written values. |

```swift
import SwiftKit

let configuration = SwiftKitConfiguration(
    environment: .development,
    keychainService: "com.example.app.storage",
    keychainAccessibility: .afterFirstUnlockThisDeviceOnly
)

try SwiftKit.initialize(configuration: configuration)
```

## Accessibility Policies
| Policy | When the value is readable | Migrates with backups |
|---|---|---|
| `.whenUnlocked` | Only while the device is unlocked | Yes |
| `.whenUnlockedThisDeviceOnly` | Only while the device is unlocked | No |
| `.afterFirstUnlock` | After the first unlock following a reboot | Yes |
| `.afterFirstUnlockThisDeviceOnly` | After the first unlock following a reboot | No |
| `.whenPasscodeSetThisDeviceOnly` | Only when a device passcode is set | No |

Use a `ThisDeviceOnly` policy for credentials that should never be restored onto another device.

## Usage

### Strings
```swift
let storage = SwiftKit.shared.secureStorage

try storage.setString("jwt-token-value", forKey: "authToken")

let token = try storage.string(forKey: "authToken")
```

### Raw Data
```swift
let payload = Data("binary-payload".utf8)
try storage.setData(payload, forKey: "sessionData")

let storedPayload = try storage.data(forKey: "sessionData")
```

### Codable Values
```swift
struct UserProfile: Codable {
    let identifier: String
    let displayName: String
}

let profile = UserProfile(identifier: "usr_1", displayName: "Archana")
try storage.setCodable(profile, forKey: "profile")

let storedProfile = try storage.codable(UserProfile.self, forKey: "profile")
```

### Existence and Removal
```swift
if storage.contains("authToken") {
    try storage.remove(forKey: "authToken")
}

// Removes every value stored under the configured keychain service.
try storage.removeAll()
```

## Error Handling
```swift
do {
    let token = try SwiftKit.shared.secureStorage.string(forKey: "authToken")
    print(token)
} catch let error as SecureStorageError {
    switch error {
    case .itemNotFound(let key):
        print("No value stored for \(key).")
    case .invalidKey:
        print("The supplied key is blank.")
    case .readFailed(let status), .writeFailed(let status),
         .updateFailed(let status), .deleteFailed(let status):
        print("Keychain operation failed with OSStatus \(status).")
    case .encodingFailed, .decodingFailed, .invalidData:
        print("The stored value could not be encoded or decoded.")
    }
}
```

## Security Notes
- Stored values are never logged. Failure diagnostics include only the operation and error case/status.
- Account keys are not written to logs.
- The default policy is `.afterFirstUnlockThisDeviceOnly`, which supports background access after the first unlock and prevents migration to another device.
- Keychain storage is intended for small, sensitive values. Do not use it as a general-purpose database.

## Thread Safety & Testing
- `KeychainStorage` is `Sendable`; all stored properties are immutable and its dependencies are `Sendable`.
- `KeychainClient` can be replaced with an in-memory implementation for unit tests without touching the system Keychain.
- The real-Keychain smoke test is skipped unless `SWIFTKIT_RUN_KEYCHAIN_TESTS=1` is set.

```bash
swift test --filter SecureStorageTests
```
