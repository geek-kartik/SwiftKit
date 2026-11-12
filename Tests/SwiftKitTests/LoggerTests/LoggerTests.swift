import XCTest
@testable import SwiftKit

final class LoggerTests: XCTestCase {
    func testLogLevelOrdering() {
        XCTAssertLessThan(LogLevel.debug, LogLevel.info)
        XCTAssertLessThan(LogLevel.info, LogLevel.warning)
        XCTAssertLessThan(LogLevel.warning, LogLevel.error)
        XCTAssertLessThan(LogLevel.error, LogLevel.none)
    }

    func testBearerTokenMasking() {
        let raw = "Authorization: Bearer secret_token_value_12345"
        let masked = DataMasker.mask(raw)

        XCTAssertFalse(masked.contains("secret_token_value_12345"))
        XCTAssertTrue(masked.contains("Bearer [REDACTED]"))
    }

    func testEmailMasking() {
        let raw = "Sending email to alice@example.com for verification"
        let masked = DataMasker.mask(raw)

        XCTAssertFalse(masked.contains("alice@example.com"))
        XCTAssertTrue(masked.contains("@example.com"))
    }

    func testJSONSensitiveKeyMasking() {
        let jsonString = "{\"password\": \"mySecretPassword123\", \"userId\": \"usr_1\"}"
        let masked = DataMasker.mask(jsonString)

        XCTAssertFalse(masked.contains("mySecretPassword123"))
        XCTAssertTrue(masked.contains("\"password\": \"********\""))
    }

    func testLogConfigurationDefaults() {
        let config = LogConfiguration()
        XCTAssertEqual(config.minimumLevel, .debug)
        XCTAssertTrue(config.isMaskingEnabled)
        XCTAssertEqual(config.category, "SwiftKit")
    }
}
