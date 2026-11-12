import Foundation

/// Centralized entry point and facade for the SwiftKit SDK.
public final class SwiftKit: @unchecked Sendable {
    private static let lock = NSLock()
    private static var instance: SwiftKit?

    private let container: SDKDependencyContainer

    /// The validated active configuration.
    public var configuration: SwiftKitConfiguration {
        container.configuration
    }

    /// Access to unified diagnostic logger.
    public var logger: LoggerProtocol {
        container.logger
    }

    // MARK: - Initialization Lifecycle

    private init(container: SDKDependencyContainer) {
        self.container = container
    }

    /// Checks whether SwiftKit has already been initialized.
    public static var isInitialized: Bool {
        lock.lock()
        defer { lock.unlock() }
        return instance != nil
    }

    /// Centralized SDK initialization entry point.
    /// - Parameter configuration: The configuration settings to apply.
    /// - Throws: `SDKError.alreadyInitialized` if previously initialized, or `SDKError.invalidConfiguration`.
    public static func initialize(configuration: SwiftKitConfiguration) throws {
        lock.lock()
        defer { lock.unlock() }

        guard instance == nil else {
            throw SDKError.alreadyInitialized
        }

        try configuration.validate()

        let container = SDKDependencyContainer(configuration: configuration)
        let newInstance = SwiftKit(container: container)
        instance = newInstance

        newInstance.logger.info("SwiftKit initialized successfully in \(configuration.environment.displayName) environment.")
    }

    /// Returns the shared initialized SwiftKit instance.
    /// Precondition: `SwiftKit.initialize(configuration:)` must have succeeded beforehand.
    public static var shared: SwiftKit {
        lock.lock()
        defer { lock.unlock() }

        guard let initializedInstance = instance else {
            fatalError("SwiftKit has not been initialized. Please invoke SwiftKit.initialize(configuration:) before accessing SwiftKit.shared.")
        }
        return initializedInstance
    }

    // MARK: - Testing Support

    /// Resets the singleton state for unit testing purposes.
    internal static func resetForTesting() {
        lock.lock()
        defer { lock.unlock() }
        instance = nil
    }

    /// Allows injecting a customized container for mock-based unit tests.
    internal static func initializeForTesting(container: SDKDependencyContainer) {
        lock.lock()
        defer { lock.unlock() }
        instance = SwiftKit(container: container)
    }
}
