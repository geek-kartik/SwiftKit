import Foundation

/// Internal dependency injection container assembling and wiring SwiftKit components.
internal final class SDKDependencyContainer: Sendable {
    internal let configuration: SwiftKitConfiguration
    internal let logger: LoggerProtocol
    internal let connectivity: ConnectivityMonitorProtocol

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
        self.connectivity = NetworkConnectivityMonitor(logger: logger)
    }

    /// Custom initializer permitting dependency injection for unit testing.
    internal init(
        configuration: SwiftKitConfiguration,
        logger: LoggerProtocol,
        connectivityMonitor: ConnectivityMonitorProtocol? = nil
    ) {
        self.configuration = configuration
        self.logger = logger
        self.connectivity = connectivityMonitor ?? NetworkConnectivityMonitor(logger: logger)
    }
}
