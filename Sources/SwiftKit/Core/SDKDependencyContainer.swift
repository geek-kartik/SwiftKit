import Foundation

/// Internal dependency injection container assembling and wiring SwiftKit components.
internal final class SDKDependencyContainer: @unchecked Sendable {
    internal let configuration: SwiftKitConfiguration
    internal let logger: LoggerProtocol

    /// Production assembly based on validated configuration.
    internal init(configuration: SwiftKitConfiguration) {
        self.configuration = configuration

        let logConfig = LogConfiguration(
            subsystem: configuration.subsystem,
            category: configuration.category,
            minimumLevel: configuration.isLoggingEnabled ? configuration.minimumLogLevel : .none,
            isMaskingEnabled: configuration.isMaskingEnabled
        )
        self.logger = OSLogger(configuration: logConfig)
    }

    /// Custom initializer permitting dependency injection for unit testing.
    internal init(
        configuration: SwiftKitConfiguration,
        logger: LoggerProtocol
    ) {
        self.configuration = configuration
        self.logger = logger
    }
}
