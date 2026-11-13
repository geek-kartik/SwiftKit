import Foundation

/// Internal dependency injection container assembling and wiring SwiftKit components.
internal final class SDKDependencyContainer: Sendable {
    internal let configuration: SwiftKitConfiguration
    internal let logger: LoggerProtocol
    internal let secureStorage: SecureStorageProtocol

    /// Internal assembly based on validated configuration.
    internal init(configuration: SwiftKitConfiguration) {
        self.configuration = configuration

        let logConfig = LogConfiguration(
            subsystem: configuration.subsystem,
            category: configuration.category,
            minimumLevel: configuration.minimumLogLevel,
            isMaskingEnabled: configuration.isMaskingEnabled,
            isEnabled: configuration.isLoggingEnabled
        )
        let logger = OSLogger(configuration: logConfig)
        self.logger = logger
        self.secureStorage = KeychainStorage(
            service: configuration.keychainService,
            accessibility: configuration.keychainAccessibility,
            logger: logger
        )
    }

    /// Custom initializer permitting dependency injection for unit testing.
    internal init(
        configuration: SwiftKitConfiguration,
        logger: LoggerProtocol,
        secureStorage: SecureStorageProtocol? = nil
    ) {
        self.configuration = configuration
        self.logger = logger
        self.secureStorage = secureStorage ?? KeychainStorage(
            service: configuration.keychainService,
            accessibility: configuration.keychainAccessibility,
            logger: logger
        )
    }
}
