# Secure Storage Module

Keychain-backed storage for tokens, credentials, and small `Codable` payloads. Clients use `SecureStorageProtocol`; the `Security` framework stays internal.

## Public API

```swift
public protocol SecureStorageProtocol: Sendable {
    func setData(_ data: Data, forKey key: String) throws
    func data(forKey key: String) throws -> Data
    func setString(_ value: String, forKey key: String) throws
    func string(forKey key: String) throws -> String
    func setCodable<T: Encodable>(_ value: T, forKey key: String) throws
    func codable<T: Decodable>(_ type: T.Type, forKey key: String) throws -> T
    func contains(_ key: String) -> Bool
    func remove(forKey key: String) throws
    func removeAll() throws
}
```

Keys must be non-empty. `contains` is `true` only when a readable value exists; removing a missing key succeeds. `removeAll()` removes every item under the configured keychain service only.

## Configuration

| `SwiftKitConfiguration` option | Default | Description |
|---|---|---|
| `keychainService` | Host bundle ID or `"com.swiftkit.sdk"` | Keychain service namespace. |
| `keychainAccessibility` | `.afterFirstUnlockThisDeviceOnly` | Policy applied to newly written values. |

```swift
let configuration = SwiftKitConfiguration(
    keychainService: "com.example.app.storage",
    keychainAccessibility: .afterFirstUnlockThisDeviceOnly
)
try SwiftKit.initialize(configuration: configuration)
```

Available policies: `.whenUnlocked`, `.whenUnlockedThisDeviceOnly`, `.afterFirstUnlock`, `.afterFirstUnlockThisDeviceOnly`, and `.whenPasscodeSetThisDeviceOnly`. Use a `ThisDeviceOnly` policy for values that must never migrate to another device.

## Usage

```swift
let storage = SwiftKit.shared.secureStorage

try storage.setString("jwt-token-value", forKey: "authToken")
let token = try storage.string(forKey: "authToken")

let payload = Data("binary-payload".utf8)
try storage.setData(payload, forKey: "sessionData")
let storedPayload = try storage.data(forKey: "sessionData")

struct UserProfile: Codable {
    let identifier: String
    let displayName: String
}

let profile = UserProfile(identifier: "usr_1", displayName: "Archana")
try storage.setCodable(profile, forKey: "profile")
let storedProfile = try storage.codable(UserProfile.self, forKey: "profile")

if storage.contains("authToken") {
    try storage.remove(forKey: "authToken")
}
try storage.removeAll()
```

`Codable` values are stored as UTF-8 JSON; invalid values produce `.encodingFailed` or `.decodingFailed`.

## Error handling

`SecureStorageError` cases: `.invalidKey`, `.itemNotFound(key:)`, `.writeFailed(status:)`, `.updateFailed(status:)`, `.deleteFailed(status:)`, `.readFailed(status:)`, `.encodingFailed`, `.decodingFailed`, and `.invalidData(key:)`.

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

## Files and implementation notes

- `Public/SecureStorageProtocol.swift`, `Public/SecureStorageError.swift`, `Public/SecureStorageAccessibility.swift`: public surface.
- `Internal/KeychainStorage.swift`: validates keys and logs failures through `LoggerProtocol`.
- `Internal/KeychainClient.swift` and `Internal/SystemKeychainClient.swift`: injectable Keychain abstraction; items use `kSecClassGenericPassword` and the data-protection Keychain.
- String and `Codable` conveniences have default protocol implementations; `KeychainStorage` handles only raw `Data`.
- Values and account keys are never logged. Failure logs include the operation and error case/status only.
- Biometric access policies and keychain access groups are not implemented.
- The concrete storage is `Sendable` with immutable dependencies; tests can inject an in-memory `KeychainClient`. A real-Keychain smoke test is skipped unless `SWIFTKIT_RUN_KEYCHAIN_TESTS=1` is set.

```bash
swift test --filter SecureStorageTests
```
