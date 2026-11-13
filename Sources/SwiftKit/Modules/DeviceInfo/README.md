# Device Info Module

## Purpose & Scope
Provides read-only device model, operating system, application version, and build environment information. The module is protocol-driven and headless-safe, allowing client applications and unit tests to consume device metadata without touching `UIKit` or hardware runtime singletons.

This module intentionally excludes screen bounds, battery state, locale, and connectivity metrics.

## Apple Frameworks
- `Foundation` (`Bundle`, `ProcessInfo`)
- `Darwin` (`utsname`, `uname`)

## Module Owner
Developer 1

## Architecture
- `Public/DeviceInfoProtocol.swift`: Public read-only contract plus version comparison helpers.
- `Internal/SystemDeviceInfo.swift`: Concrete `DeviceInfoProtocol` implementation backed by `Bundle` and `ProcessInfo`.
- `Internal/SemanticVersion.swift`: Internal numeric version parser used for comparison helpers.

## Public API
| Member | Type | Description |
|---|---|---|
| `deviceModel` | `String` | Hardware machine identifier from `utsname.machine` (for example, `iPhone15,3`, `arm64`). |
| `osVersion` | `String` | Operating system version string from `ProcessInfo`. |
| `appVersion` | `String` | Marketing version (`CFBundleShortVersionString`), defaulting to `0.0.0`. |
| `buildNumber` | `String` | Build number (`CFBundleVersion`), defaulting to `0`. |
| `bundleIdentifier` | `String` | Host bundle identifier, defaulting to `unknown`. |
| `appName` | `String` | `CFBundleDisplayName` falling back to `CFBundleName`, defaulting to `unknown`. |
| `isSimulator` | `Bool` | `true` when running on a simulator. |
| `isDebugBuild` | `Bool` | `true` when compiled with debug assertions. |
| `isAppVersionAtLeast(_:)` | `Bool` | Compares `appVersion` against a minimum version. |
| `isUpdateRequired(minimumVersion:)` | `Bool` | `true` when `appVersion` is below the minimum version. |
| `isOSVersionAtLeast(_:)` | `Bool` | Compares the current OS version against a minimum version. |

## Usage
```swift
let deviceInfo = SwiftKit.shared.deviceInfo

print(deviceInfo.deviceModel)       // e.g. "iPhone15,3"
print(deviceInfo.osVersion)         // e.g. "Version 18.1 (Build 22B83)"
print(deviceInfo.appVersion)        // e.g. "2.4.1"
print(deviceInfo.buildNumber)       // e.g. "42"
print(deviceInfo.bundleIdentifier)  // e.g. "com.example.app"
print(deviceInfo.appName)           // e.g. "Example"
print(deviceInfo.isSimulator)       // false on physical devices
print(deviceInfo.isDebugBuild)      // true in debug builds
```

## Version Helpers
Use the comparison helpers to drive minimum-version and force-update checks after fetching the required version from your backend.

```swift
if deviceInfo.isUpdateRequired(minimumVersion: "2.5.0") {
    // Prompt the user to update the application.
}

if deviceInfo.isAppVersionAtLeast("2.0.0") {
    // Enable newer features.
}

if deviceInfo.isOSVersionAtLeast("17.0") {
    // Use APIs that require iOS 17 or later.
}
```

Comparison rules:
- Versions are parsed as dotted numeric components (`1.10.0` is greater than `1.9.0`).
- Missing components are treated as zero (`1.2` equals `1.2.0`).
- Pre-release suffixes are ignored (`1.0.0-beta` equals `1.0.0`).
- Invalid or empty input returns `false` instead of throwing.

## Headless Testing
- `SystemDeviceInfo` accepts an injected `Bundle`, OS version values, and simulator/debug flags.
- Unit tests run on macOS hosts via `swift test` without requiring `UIKit` or a simulator.
- `isOSVersionAtLeast` uses numeric `ProcessInfo.processInfo.operatingSystemVersion` components rather than parsing the display string.

```bash
swift test --filter DeviceInfoTests
```
