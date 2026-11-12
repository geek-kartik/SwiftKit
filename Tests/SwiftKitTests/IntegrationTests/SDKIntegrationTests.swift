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
    }
}
