import XCTest
@testable import SwiftKit

final class LoggerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        SwiftKit.resetForTesting()
    }

    override func tearDown() {
        SwiftKit.resetForTesting()
        super.tearDown()
    }

    // MARK: - LogLevel

    func testLogLevelOrdering() {
        XCTAssertLessThan(LogLevel.debug, LogLevel.info)
        XCTAssertLessThan(LogLevel.info, LogLevel.warning)
        XCTAssertLessThan(LogLevel.warning, LogLevel.error)
        XCTAssertLessThan(LogLevel.error, LogLevel.none)
    }

    func testLogLevelLabels() {
        XCTAssertEqual(LogLevel.debug.label, "DEBUG")
        XCTAssertEqual(LogLevel.info.label, "INFO")
        XCTAssertEqual(LogLevel.warning.label, "WARNING")
        XCTAssertEqual(LogLevel.error.label, "ERROR")
        XCTAssertEqual(LogLevel.none.label, "NONE")
    }

    // MARK: - Configuration

    func testLogConfigurationDefaults() {
        let config = LogConfiguration()

        XCTAssertEqual(config.subsystem, "com.swiftkit.sdk")
        XCTAssertEqual(config.category, "SwiftKit")
        XCTAssertEqual(config.minimumLevel, .debug)
        XCTAssertTrue(config.isMaskingEnabled)
        XCTAssertTrue(config.isEnabled)
    }

    func testLogConfigurationCustomValues() {
        let config = LogConfiguration(
            subsystem: "com.swiftkit.tests",
            category: "Custom",
            minimumLevel: .warning,
            isMaskingEnabled: false,
            isEnabled: false
        )

        XCTAssertEqual(config.subsystem, "com.swiftkit.tests")
        XCTAssertEqual(config.category, "Custom")
        XCTAssertEqual(config.minimumLevel, .warning)
        XCTAssertFalse(config.isMaskingEnabled)
        XCTAssertFalse(config.isEnabled)
    }

    // MARK: - Mock logger

    func testMockLoggerRecordsEachLevel() {
        let logger = MockLogger()

        logger.debug("debug entry")
        logger.info("info entry")
        logger.warning("warning entry")
        logger.error("error entry")

        XCTAssertEqual(logger.recordedLevels, [.debug, .info, .warning, .error])
        XCTAssertEqual(
            logger.recordedEntries.map(\.message),
            ["debug entry", "info entry", "warning entry", "error entry"]
        )
    }

    // MARK: - OSLogger filtering

    func testMinimumLevelFiltersLowerSeverities() {
        let output = RecordingLogOutput()
        let logger = OSLogger(
            configuration: LogConfiguration(minimumLevel: .warning),
            output: output
        )

        logger.debug("debug entry")
        logger.info("info entry")
        logger.warning("warning entry")
        logger.error("error entry")

        XCTAssertEqual(output.recordedLevels, [.warning, .error])
    }

    func testDisabledConfigurationSuppressesAllLevels() {
        let output = RecordingLogOutput()
        let logger = OSLogger(
            configuration: LogConfiguration(isEnabled: false),
            output: output
        )

        logger.debug("debug entry")
        logger.info("info entry")
        logger.warning("warning entry")
        logger.error("error entry")

        XCTAssertTrue(output.recordedEntries.isEmpty)
    }

    func testNoneMinimumLevelSuppressesAllLevels() {
        let output = RecordingLogOutput()
        let logger = OSLogger(
            configuration: LogConfiguration(minimumLevel: .none),
            output: output
        )

        logger.debug("debug entry")
        logger.info("info entry")
        logger.warning("warning entry")
        logger.error("error entry")

        XCTAssertTrue(output.recordedEntries.isEmpty)
    }

    // MARK: - Security

    func testSensitiveMessageIsMaskedBeforeDispatch() {
        let output = RecordingLogOutput()
        let logger = OSLogger(
            configuration: LogConfiguration(isMaskingEnabled: true),
            output: output
        )

        logger.info("Authorization: Bearer secret_token_value_12345")

        let message = output.recordedEntries.first?.message ?? ""
        XCTAssertFalse(message.contains("secret_token_value_12345"))
        XCTAssertTrue(message.contains("Bearer [REDACTED]"))
    }

    func testMaskingCanBeDisabled() {
        let output = RecordingLogOutput()
        let logger = OSLogger(
            configuration: LogConfiguration(isMaskingEnabled: false),
            output: output
        )

        logger.info("plain message")

        XCTAssertEqual(output.recordedEntries.first?.message, "plain message")
    }

    // MARK: - Conformance & thread safety

    func testOSLoggerConformsToLoggerProtocol() {
        let logger: LoggerProtocol = OSLogger(configuration: LogConfiguration())
        XCTAssertNotNil(logger)
    }

    func testConcurrentLoggingIsThreadSafe() {
        let output = RecordingLogOutput()
        let logger = OSLogger(configuration: LogConfiguration(), output: output)

        DispatchQueue.concurrentPerform(iterations: 200) { index in
            logger.debug("concurrent entry \(index)")
        }

        XCTAssertEqual(output.recordedEntries.count, 200)
    }

    // MARK: - Integration

    func testFacadeResolvesInjectedLogger() throws {
        let configuration = SwiftKitConfiguration(
            subsystem: "com.swiftkit.tests.logger",
            category: "LoggerTests"
        )
        let mock = MockLogger()
        let container = SDKDependencyContainer(configuration: configuration, logger: mock)

        SwiftKit.initializeForTesting(container: container)

        SwiftKit.shared.logger.info("facade entry")

        XCTAssertEqual(mock.recordedEntries.count, 1)
        XCTAssertEqual(mock.recordedEntries.first?.level, .info)
        XCTAssertEqual(mock.recordedEntries.first?.message, "facade entry")
    }
}
