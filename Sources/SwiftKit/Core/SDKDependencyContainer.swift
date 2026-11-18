import Foundation

/// Internal dependency injection container assembling and wiring SwiftKit components.
internal final class SDKDependencyContainer: Sendable {
    internal let configuration: SwiftKitConfiguration
    internal let logger: LoggerProtocol
    internal let connectivity: ConnectivityMonitorProtocol
    internal let secureStorage: SecureStorageProtocol
    internal let deviceInfo: DeviceInfoProtocol
    internal let session: SessionManagerProtocol

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
        self.deviceInfo = SystemDeviceInfo()
        self.connectivity = NetworkConnectivityMonitor(logger: logger)
        self.session = SessionManager(
            secureStorage: self.secureStorage,
            logger: logger,
            connectivity: self.connectivity,
            refreshHandler: configuration.sessionTokenRefreshHandler
        )
    }

    /// Custom initializer permitting dependency injection for unit testing.
    internal init(
        configuration: SwiftKitConfiguration,
        logger: LoggerProtocol,
        secureStorage: SecureStorageProtocol? = nil,
        deviceInfo: DeviceInfoProtocol? = nil,
        connectivityMonitor: ConnectivityMonitorProtocol? = nil,
        sessionManager: SessionManagerProtocol? = nil,
        sessionTokenRefreshHandler: SessionTokenRefreshHandler? = nil
    ) {
        self.configuration = configuration
        self.logger = logger
        self.secureStorage = secureStorage ?? KeychainStorage(
            service: configuration.keychainService,
            accessibility: configuration.keychainAccessibility,
            logger: logger
        )
        self.connectivity = connectivityMonitor ?? NetworkConnectivityMonitor(logger: logger)
        self.deviceInfo = deviceInfo ?? SystemDeviceInfo()
        self.session = sessionManager ?? SessionManager(
            secureStorage: self.secureStorage,
            logger: logger,
            connectivity: self.connectivity,
            refreshHandler: sessionTokenRefreshHandler ?? configuration.sessionTokenRefreshHandler
        )
    }
}
