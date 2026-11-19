# Logger Module

Structured diagnostics backed by Apple's `OSLog` (`os.Logger`). SDK modules take a `LoggerProtocol` dependency instead of depending on the concrete logger.

## Public API

```swift
public protocol LoggerProtocol: Sendable {
    func log(_ message: String, level: LogLevel, file: String, function: String, line: Int)
    func debug(_ message: String, file: String, function: String, line: Int)
    func info(_ message: String, file: String, function: String, line: Int)
    func warning(_ message: String, file: String, function: String, line: Int)
    func error(_ message: String, file: String, function: String, line: Int)
}
```

Convenience methods default `file`, `function`, and `line` to the call site. `LogLevel` cases are `.debug`, `.info`, `.warning`, `.error`, and `.none`. `.none` disables dispatch when used as the minimum level.

| Log level | OSLog type |
|---|---|
| `.debug` | `debug` |
| `.info` | `info` |
| `.warning` | `notice` |
| `.error` | `error` |

## Configuration

`SwiftKitConfiguration` sets `subsystem`, `category`, `minimumLogLevel` (default `.debug`), `isMaskingEnabled` (default `true`), and `isLoggingEnabled` (default `true`) on the internal `LogConfiguration`. Configuration is applied once during `SwiftKit.initialize(configuration:)`.

## Usage

```swift
import SwiftKit

let logger = SwiftKit.shared.logger
logger.debug("Cache warmed")
logger.info("SDK initialized")
logger.warning("Network path unavailable")
logger.error("Request failed")

// Explicit source context (the convenience methods supply these automatically):
logger.log("Retrying", level: .info, file: #fileID, function: #function, line: #line)
```

Modules that accept a logger should depend on the protocol:

```swift
internal final class SomeModule {
    private let logger: LoggerProtocol

    internal init(logger: LoggerProtocol) {
        self.logger = logger
    }
}
```

## Files and dependencies

- `Public/LoggerProtocol.swift`, `Public/LogLevel.swift`: public contract and severity levels.
- `Models/LogConfiguration.swift`: immutable configuration value.
- `Internal/OSLogger.swift`: filters by level, applies masking, then writes through an internal `LogOutput`. `OSLogOutput` maps levels and marks dynamic message text with OSLog `.private` privacy.
- Uses `OSLog`, `Foundation`, and the shared `DataMasker`.

## Security notes

- `DataMasker` redacts Bearer tokens, emails, and sensitive JSON keys before dispatch when masking is enabled. OSLog `.private` interpolation is an additional layer.
- Do not pass tokens, passwords, card data, Authorization headers, or raw request/response bodies as log messages.
- Masking and logging are enabled by default; keep them enabled in production.

## Testing

`OSLogger` accepts an injected `LogOutput`, so filtering and masking are tested without reading the system console.

```bash
swift test --filter LoggerTests
```
