import XCTest
@testable import SwiftKit

final class SwiftKitTests: XCTestCase {
    override func setUp() {
        super.setUp()
        SwiftKit.resetForTesting()
    }

    override func tearDown() {
        SwiftKit.resetForTesting()
        super.tearDown()
    }

    func testSDKInitializationLifecycle() throws {
        XCTAssertFalse(SwiftKit.isInitialized)

        let config = SwiftKitConfiguration(
            environment: .development,
            subsystem: "com.swiftkit.test",
            category: "CoreTests"
        )

        try SwiftKit.initialize(configuration: config)

        XCTAssertTrue(SwiftKit.isInitialized)
        XCTAssertNotNil(SwiftKit.shared)
        XCTAssertTrue((try SwiftKit.resolvedShared()) === SwiftKit.shared)
        XCTAssertEqual(SwiftKit.shared.configuration.environment, .development)
        XCTAssertNotNil(SwiftKit.shared.logger)
        XCTAssertNotNil(SwiftKit.shared.secureStorage)
        XCTAssertNotNil(SwiftKit.shared.deviceInfo)
    }

    func testResolvedSharedThrowsNotInitialized() {
        XCTAssertThrowsError(try SwiftKit.resolvedShared()) { error in
            XCTAssertEqual(error as? SDKError, .notInitialized)
        }
    }

    func testResolveThrowsNotInitializedBeforeInitialization() {
        XCTAssertThrowsError(try SwiftKit.resolve(LoggerProtocol.self)) { error in
            XCTAssertEqual(error as? SDKError, .notInitialized)
        }
    }

    func testFacadeResolvesInjectedSecureStorage() throws {
        let config = SwiftKitConfiguration(environment: .development)
        let logger = MockLogger()
        let storage = KeychainStorage(
            service: "com.swiftkit.tests.facade",
            client: InMemoryKeychainClient(),
            logger: logger
        )
        let container = SDKDependencyContainer(
            configuration: config,
            logger: logger,
            secureStorage: storage
        )

        SwiftKit.initializeForTesting(container: container)
        try SwiftKit.shared.secureStorage.setString("secret", forKey: "token")

        XCTAssertEqual(try SwiftKit.shared.secureStorage.string(forKey: "token"), "secret")
    }

    func testResolveReturnsRegisteredDependencies() throws {
        let config = SwiftKitConfiguration(
            subsystem: "com.swiftkit.tests.resolve",
            category: "CoreTests"
        )
        let logger = MockLogger()
        let storage = KeychainStorage(
            service: "com.swiftkit.tests.resolve",
            client: InMemoryKeychainClient(),
            logger: logger
        )
        let container = SDKDependencyContainer(
            configuration: config,
            logger: logger,
            secureStorage: storage
        )
        SwiftKit.initializeForTesting(container: container)

        let resolvedLogger: LoggerProtocol = try SwiftKit.resolve(LoggerProtocol.self)
        XCTAssertTrue(resolvedLogger as AnyObject === logger)

        let resolvedStorage: SecureStorageProtocol = try SwiftKit.resolve(SecureStorageProtocol.self)
        XCTAssertTrue(resolvedStorage as AnyObject === storage)

        let resolvedConfiguration: SwiftKitConfiguration = try SwiftKit.resolve(SwiftKitConfiguration.self)
        XCTAssertEqual(resolvedConfiguration.subsystem, config.subsystem)
    }

    func testResolveThrowsDependencyMissingForUnregisteredType() throws {
        try SwiftKit.initialize(
            configuration: SwiftKitConfiguration(
                subsystem: "com.swiftkit.tests.resolve",
                category: "CoreTests"
            )
        )

        XCTAssertThrowsError(try SwiftKit.resolve(Date.self)) { error in
            XCTAssertEqual(
                error as? SDKError,
                .dependencyMissing(dependencyName: String(describing: Date.self))
            )
        }
    }

    func testDoubleInitializationThrowsError() throws {
        let config = SwiftKitConfiguration(environment: .development)

        try SwiftKit.initialize(configuration: config)

        XCTAssertThrowsError(try SwiftKit.initialize(configuration: config)) { error in
            XCTAssertEqual(error as? SDKError, .alreadyInitialized)
        }
    }

    func testResetForTesting() throws {
        let config = SwiftKitConfiguration(environment: .development)

        try SwiftKit.initialize(configuration: config)
        XCTAssertTrue(SwiftKit.isInitialized)

        SwiftKit.resetForTesting()
        XCTAssertFalse(SwiftKit.isInitialized)
    }
}
