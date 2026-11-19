# SwiftKit Sample App

A SwiftUI app (iOS 15+) that demonstrates all SwiftKit modules through the SDK's public APIs. It runs fully offline: a custom `URLProtocol` intercepts requests to `https://sample.swiftkit.test`, so no backend or API keys are needed.

See the [root README](../README.md) for SDK installation and module documentation.

## Prerequisites

- Xcode 15.0+ with an iOS 15.0+ simulator
- macOS with command-line tools for `xcodebuild`
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) only if you want to regenerate the project from `project.yml` (the committed `SampleApp.xcodeproj` is ready to use)

## Build and run

Open `SampleApp/SampleApp.xcodeproj`, select the **SampleApp** scheme and a simulator, then run. The SDK is included as a local Swift package (`path: ..`) via `project.yml`.

From the repository root:

```bash
xcodebuild build -project SampleApp/SampleApp.xcodeproj \
  -scheme SampleApp \
  -destination "generic/platform=iOS Simulator" \
  CODE_SIGNING_ALLOWED=NO
```

Replace the destination with an installed simulator to run unit tests, for example:

```bash
xcodebuild test -project SampleApp/SampleApp.xcodeproj \
  -scheme SampleApp \
  -destination "platform=iOS Simulator,name=iPhone 17" \
  CODE_SIGNING_ALLOWED=NO
```

`swift build` and `swift test` at the repository root build only the SDK package; the sample app has no `Package.swift` and must be built with Xcode.

## Configuration

No environment variables, secrets, or `.env` files are required. Setup lives in `Sources/App/SampleApp.swift`:

| Setting | Value |
|---|---|
| OSLog subsystem / category | `com.swiftkit.sampleapp` / `SampleApp` |
| Keychain service | `com.swiftkit.sampleapp.storage` |
| Network base URL | `https://sample.swiftkit.test` |
| Default header | `X-Sample-App: SwiftKit-Sample` |
| Accessibility | `.afterFirstUnlockThisDeviceOnly` |
| Session refresh | `SampleSessionRefreshHandler` (calls the offline backend) |

`SampleURLProtocol` in `Sources/Services/SampleBackend.swift` is registered at launch and answers:

| Path | Behavior |
|---|---|
| `/v1/auth/refresh` | Issues refreshed tokens; first call uses stale-token simulation |
| `/v1/protected` | Returns 401 until the token has been refreshed |
| `/v1/failure` | 500 |
| `/v1/bad-json` | Malformed JSON |
| `/v1/not-found` | 404 |
| Other `/v1/...` paths | Successful JSON response |

## What the app demonstrates

| Module | Flow |
|---|---|
| Core | `SwiftKit.initialize(configuration:)` at launch; `SDKService` wraps `SwiftKit.shared` for injection into view models |
| Secure Storage | Keychain string/data/`Codable` round trips, `contains`, `remove`, `removeAll`; the app validates empty input locally |
| Device Info | Metadata display and `isUpdateRequired`, `isAppVersionAtLeast`, `isOSVersionAtLeast` checks |
| Connectivity | `start`/`stop`, observer tokens, status timeline; callbacks hop to the main actor for UI |
| Logger | All severity levels, custom `log` with source context, and masking demo with `DataMasker` |
| Session | Start, restore, sync and async refresh, observers, expiry, logout, and simulated 401 handling |
| Networking | All five HTTP verbs, JSON encode/decode, bearer token from `tokenProvider`, error callbacks, and app-level `401 → refreshSession() → retry once` |

## Project layout

```text
SampleApp/
├── project.yml                # XcodeGen spec (local SwiftKit package)
├── SampleApp.xcodeproj
├── Resources/Info.plist
├── Sources/
│   ├── App/SampleApp.swift    # SDK setup and app entry point
│   ├── Services/              # SDKService facade wrapper, offline backend
│   ├── Models/                # Sample Codable profile
│   ├── ViewModels/            # @MainActor state per module
│   └── Views/                 # Dashboard plus one screen per module
└── Tests/SampleAppTests/      # ViewModel tests with mocks and URLProtocol tests
```

Synchronous `refreshSession(accessToken:refreshToken:expiresAt:)` uses literal values from the UI; only the async `refreshSession()` uses the configured refresh handler. Token refresh and 401 retry are implemented by the sample, not by SwiftKit.
