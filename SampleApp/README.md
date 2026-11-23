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
  -destination "generic/platform=iOS Simulator"
```

Replace the destination with an installed simulator to run unit tests, for example:

```bash
xcodebuild test -project SampleApp/SampleApp.xcodeproj \
  -scheme SampleApp \
  -destination "platform=iOS Simulator,name=iPhone 17"
```

The app target is manually ad-hoc signed for simulator builds (`CODE_SIGN_STYLE=Manual`, `CODE_SIGN_IDENTITY="-"`, empty team/profile). It should build and run on any Mac with Xcode simulators installed, without Apple Developer provisioning. Keychain behavior can vary on entitlement-less simulator builds; if Secure Storage/Session persistence reports a Keychain entitlement error on a specific host, run with a signed entitlement-enabled build.

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
| URL session | `sessionConfigurationFactory` installs `SampleURLProtocol` so the offline backend answers every request |

`SampleURLProtocol` in `Sources/Services/SampleBackend.swift` is installed in the SDK client's URL session configuration and answers:

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
| Networking | All five HTTP verbs, raw JSON body passthrough with editable headers, timeout, and cache policy, raw response metadata, bearer token from `tokenProvider`, duplicate suppression and in-flight tracking, cancel, session-aware logout/expiry cancellation, configuration callbacks, 404/500/decoding failures, developer-controlled logging, and app-level `401 → single-flight refreshSession() → retry once` |

## Project layout

```text
SampleApp/
├── project.yml                # XcodeGen spec (local SwiftKit package)
├── SampleApp.xcodeproj
├── Resources/
│   ├── Info.plist
│   └── SampleApp.entitlements # Keychain access group for simulator builds
├── Sources/
│   ├── App/SampleApp.swift    # SDK setup and app entry point
│   ├── Services/              # SDKService facade wrapper, offline backend
│   ├── Models/                # Sample Codable profile
│   ├── ViewModels/            # @MainActor state per module
│   └── Views/                 # Dashboard plus one screen per module
└── Tests/SampleAppTests/      # ViewModel tests with mocks and URLProtocol tests
```

Synchronous `refreshSession(accessToken:refreshToken:expiresAt:)` uses literal values from the UI; only the async `refreshSession()` uses the configured refresh handler. Concurrent `401`s share one refresh, logout or expiry skips refresh and retry, and a second `401` clears the session. Token refresh and 401 retry are implemented by the sample, not by SwiftKit.
