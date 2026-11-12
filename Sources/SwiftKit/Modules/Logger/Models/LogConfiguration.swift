import Foundation

/// Operational settings governing the SwiftKit logging module.
public struct LogConfiguration: Sendable {
    /// Apple OSLog subsystem identifier (e.g. bundle identifier).
    public let subsystem: String

    /// Apple OSLog category (e.g. "SwiftKit").
    public let category: String

    /// Minimum threshold level required for messages to be dispatched.
    public let minimumLevel: LogLevel

    /// Governs whether sensitive patterns (Bearer tokens, emails, keys) are redacted.
    public let isMaskingEnabled: Bool

    public init(
        subsystem: String = "com.swiftkit.sdk",
        category: String = "SwiftKit",
        minimumLevel: LogLevel = .debug,
        isMaskingEnabled: Bool = true
    ) {
        self.subsystem = subsystem
        self.category = category
        self.minimumLevel = minimumLevel
        self.isMaskingEnabled = isMaskingEnabled
    }
}
