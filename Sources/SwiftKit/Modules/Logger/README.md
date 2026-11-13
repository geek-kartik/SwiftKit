# Logger Module

## Purpose & Scope
Provides unified, performant logging backed by Apple's `OSLog` (`os.Logger`) framework with automatic data redaction for security-sensitive tokens and credentials. The module is consumed by every other SDK module through the `LoggerProtocol` abstraction.

## Apple Frameworks
- `OSLog` (`os.Logger`, `OSLogType`)
- `Foundation`

## Architecture
- `Public/LoggerProtocol.swift`: Public logging contract (`debug`, `info`, `warning`, `error`, `log`).
- `Public/LogLevel.swift`: Public severity enum (`.debug`, `.info`, `.warning`, `.error`, `.none`).
- `Models/LogConfiguration.swift`: Operational configuration value type.
- `Internal/OSLogger.swift`: Concrete `LoggerProtocol` implementation. Delegates dispatch to an internal `LogOutput`, allowing filtering and sanitization to be unit tested without reading the system Console.

## Supported Log Levels
| Level | OSLog mapping | Purpose |
|---|---|---|
| `.debug` | `debug` | Development diagnostics |
| `.info` | `info` | Informational lifecycle events |
| `.warning` | `notice` | Non-fatal anomalies |
| `.error` | `error` | Failure conditions |
| `.none` | none | Disables all dispatch when used as `minimumLevel` |

## Configuration
`LogConfiguration` supports:
- `subsystem`: OSLog subsystem identifier.
- `category`: OSLog category.
- `minimumLevel`: Lowest severity that is dispatched.
- `isMaskingEnabled`: Redacts sensitive patterns before dispatch (default `true`).
- `isEnabled`: Master switch for logging (default `true`).

`SwiftKitConfiguration` maps `subsystem`, `category`, `minimumLogLevel`, `isMaskingEnabled`, and `isLoggingEnabled` onto `LogConfiguration` during SDK initialization.

## Usage Example
```swift
import SwiftKit

let logger = SwiftKit.shared.logger

logger.debug("Debug message")
logger.info("SDK initialized")
logger.warning("Connectivity is unstable")
logger.error("Network request failed")
```

Dependency injection for module authors:
```swift
internal final class SomeModule {
    private let logger: LoggerProtocol

    internal init(logger: LoggerProtocol) {
        self.logger = logger
    }
}
```

## Security & Privacy
- Dynamic message bodies are emitted with OSLog `privacy: .private`; only the level, source file, line, and function are public.
- `DataMasker` redacts Bearer tokens, email addresses, and sensitive JSON keys before dispatch when `isMaskingEnabled` is enabled.
- Never pass authentication tokens, passwords, PINs, card data, Authorization headers, or raw request/response bodies as log messages.
- Privacy annotations are used in addition to masking, so sensitive dynamic values are not exposed even if masking is misconfigured.
- Logging is safe by default: masking and logging are both enabled unless explicitly disabled by the host application.
