import Foundation

/// Encapsulates initialization parameters and operational settings for SwiftKit and its logging subsystem.
public struct SwiftKitConfiguration: Sendable {
    /// Active SDK target environment (development mode only).
    public let environment: SDKEnvironment

    /// Subsystem identifier for Apple OSLog.
    public let subsystem: String

    /// Category label for Apple OSLog.
    public let category: String

    /// Minimum threshold level for log messages to be dispatched.
    public let minimumLogLevel: LogLevel

    /// Governs whether sensitive patterns (Bearer tokens, emails, passwords) are automatically redacted.
    public let isMaskingEnabled: Bool

    /// Global flag enabling or disabling logging entirely.
    public let isLoggingEnabled: Bool

    /// Initializes a new configuration instance for SwiftKit.
    /// - Parameters:
    ///   - environment: The target runtime environment (`.development`). Defaults to `.development`.
    ///   - subsystem: OSLog subsystem identifier. Defaults to host bundle ID or `"com.swiftkit.sdk"`.
    ///   - category: OSLog category. Defaults to `"SwiftKit"`.
    ///   - minimumLogLevel: Minimum log severity threshold. Defaults to `.debug` for internal development.
    ///   - isMaskingEnabled: Redacts sensitive tokens and personal data when `true`. Defaults to `true`.
    ///   - isLoggingEnabled: Master toggle for logging. Defaults to `true`.
    public init(
        environment: SDKEnvironment = .development,
        subsystem: String = Bundle.main.bundleIdentifier ?? "com.swiftkit.sdk",
        category: String = "SwiftKit",
        minimumLogLevel: LogLevel? = nil,
        isMaskingEnabled: Bool = true,
        isLoggingEnabled: Bool = true
    ) {
        self.environment = environment
        self.subsystem = subsystem
        self.category = category
        self.minimumLogLevel = minimumLogLevel ?? .debug
        self.isMaskingEnabled = isMaskingEnabled
        self.isLoggingEnabled = isLoggingEnabled
    }

    /// Validates configuration parameters.
    /// - Throws: `SDKError.invalidConfiguration` if any rule is violated.
    public func validate() throws {
        guard !subsystem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SDKError.invalidConfiguration(reason: "Logging subsystem identifier cannot be empty.")
        }

        guard !category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SDKError.invalidConfiguration(reason: "Logging category identifier cannot be empty.")
        }
    }
}
