# Logger Module

## Module Owner
**Developer 3** (Session, Logger, Permissions)

## Purpose & Scope
Provides unified, performant logging backed by Apple's `OSLog` (`os.Logger`) framework with automatic data redaction for security-sensitive tokens and credentials.

## Apple Frameworks
- `OSLog` (`os.Logger`, `OSLogType`)
- `Foundation`

## Public APIs
- `LoggerProtocol`: Interface declaring `log`, `debug`, `info`, `warning`, and `error` entry points.
- `LogLevel`: Enum providing `.debug`, `.info`, `.warning`, `.error`, and `.none`.
- `LogConfiguration`: Configuration object specifying subsystem, category, minimum level, and masking flag.

## Internal Implementation
- `OSLogger`: Dispatches formatted log lines to the unified logging system.
- `DataMasker`: Redacts Authorization tokens, passwords, API keys, and email identifiers.

## Usage Example
```swift
import SwiftKit

let logger = SwiftKit.shared.logger

logger.debug("Starting local cache inspection")
logger.info("User session established with token: Bearer abc123def456") 
// Output will automatically redact the bearer token: Bearer [REDACTED]

logger.warning("Network response took longer than 2.0s")
logger.error("Failed to fetch user permissions")
```
