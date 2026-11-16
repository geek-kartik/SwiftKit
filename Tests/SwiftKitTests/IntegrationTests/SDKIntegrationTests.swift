import XCTest
@testable import SwiftKit

final class SDKIntegrationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        SwiftKit.resetForTesting()
    }

    override func tearDown() {
        SwiftKit.resetForTesting()
        super.tearDown()
    }

    func testEndToEndInitializationAndLoggerIntegration() throws {
        let config = SwiftKitConfiguration(
            environment: .development,
            subsystem: "com.swiftkit.integration",
            category: "SDKTests",
            minimumLogLevel: .debug,
            isMaskingEnabled: true,
            isLoggingEnabled: true
        )

        try SwiftKit.initialize(configuration: config)

        let sdk = SwiftKit.shared

        // Verify Core Configuration
        XCTAssertEqual(sdk.configuration.environment, .development)
        XCTAssertEqual(sdk.configuration.subsystem, "com.swiftkit.integration")
        XCTAssertEqual(sdk.configuration.category, "SDKTests")

        // Verify Logger execution
        sdk.logger.debug("Debug log verified")
        sdk.logger.info("Session started with token: Bearer confidential_auth_token_999")
        sdk.logger.warning("Simulated resource latency warning")
        sdk.logger.error("Simulated recoverable failure")

        // Verify Session Manager wiring (no Keychain access on the real container)
        XCTAssertTrue(sdk.session is SessionManager)
        XCTAssertFalse(sdk.session.isAuthenticated)
    }

    func testEndToEndSessionManagerIntegrationWithInMemoryStorage() throws {
        let config = SwiftKitConfiguration(
            environment: .development,
            subsystem: "com.swiftkit.integration.session",
            category: "SDKTests"
        )
        let logger = MockLogger()
        let secureStorage = KeychainStorage(
            service: "com.swiftkit.integration.session",
            accessibility: .afterFirstUnlockThisDeviceOnly,
            client: InMemoryKeychainClient(),
            logger: logger
        )
        let container = SDKDependencyContainer(
            configuration: config,
            logger: logger,
            secureStorage: secureStorage
        )
        SwiftKit.initializeForTesting(container: container)

        let sdk = SwiftKit.shared
        let session = Session(
            accessToken: "integration-access-token",
            refreshToken: "integration-refresh-token",
            expiresAt: Date().addingTimeInterval(3600),
            userID: "integration-user"
        )

        try sdk.session.startSession(session)

        XCTAssertTrue(sdk.session.isAuthenticated)
        XCTAssertEqual(sdk.session.currentSession, session)

        try sdk.session.logout()
        XCTAssertFalse(sdk.session.isAuthenticated)
    }
}
