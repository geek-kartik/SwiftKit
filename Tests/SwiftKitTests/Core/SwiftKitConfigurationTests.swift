import XCTest
@testable import SwiftKit

final class SwiftKitConfigurationTests: XCTestCase {
    func testValidDevelopmentConfiguration() {
        let config = SwiftKitConfiguration(
            environment: .development,
            subsystem: "com.test.sdk",
            category: "Diagnostic",
            minimumLogLevel: .debug,
            isMaskingEnabled: true,
            isLoggingEnabled: true
        )

        XCTAssertNoThrow(try config.validate())
        XCTAssertEqual(config.environment, .development)
        XCTAssertEqual(config.minimumLogLevel, .debug)
        XCTAssertTrue(config.isMaskingEnabled)
        XCTAssertTrue(config.isLoggingEnabled)
    }

    func testEnvironmentDefaultLogLevels() {
        let devConfig = SwiftKitConfiguration(environment: .development)
        XCTAssertEqual(devConfig.minimumLogLevel, .debug)

        let defaultConfig = SwiftKitConfiguration()
        XCTAssertEqual(defaultConfig.environment, .development)
        XCTAssertEqual(defaultConfig.minimumLogLevel, .debug)
    }

    func testEmptySubsystemThrows() {
        let config = SwiftKitConfiguration(
            environment: .development,
            subsystem: "   "
        )

        XCTAssertThrowsError(try config.validate()) { error in
            guard case SDKError.invalidConfiguration(let reason) = error else {
                return XCTFail("Expected invalidConfiguration error, got \(error)")
            }
            XCTAssertTrue(reason.contains("subsystem"))
        }
    }

    func testEmptyCategoryThrows() {
        let config = SwiftKitConfiguration(
            environment: .development,
            category: "   "
        )

        XCTAssertThrowsError(try config.validate()) { error in
            guard case SDKError.invalidConfiguration(let reason) = error else {
                return XCTFail("Expected invalidConfiguration error, got \(error)")
            }
            XCTAssertTrue(reason.contains("category"))
        }
    }
}
