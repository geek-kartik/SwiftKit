import XCTest
import SwiftKit
@testable import SampleApp

@MainActor
final class LoggingViewModelTests: XCTestCase {
    private var mockLogger: MockLogger!
    private var viewModel: LoggingViewModel!

    override func setUp() {
        super.setUp()
        mockLogger = MockLogger()
        viewModel = LoggingViewModel(logger: mockLogger)
    }

    override func tearDown() {
        viewModel = nil
        mockLogger = nil
        super.tearDown()
    }

    func testLogDebugDispatches() {
        viewModel.logDebug(customText: "Debug test trace")
        XCTAssertEqual(mockLogger.loggedMessages.count, 1)
        XCTAssertEqual(mockLogger.loggedMessages.first?.level, .debug)
        XCTAssertEqual(mockLogger.loggedMessages.first?.message, "Debug test trace")
        XCTAssertEqual(viewModel.dispatchedLogs.count, 1)
        XCTAssertEqual(viewModel.dispatchedLogs.first?.level, .debug)
    }

    func testLogInfoDispatches() {
        viewModel.logInfo(customText: "Informational message")
        XCTAssertEqual(mockLogger.loggedMessages.count, 1)
        XCTAssertEqual(mockLogger.loggedMessages.first?.level, .info)
        XCTAssertEqual(mockLogger.loggedMessages.first?.message, "Informational message")
    }

    func testLogWarningDispatches() {
        viewModel.logWarning(customText: "Warning message")
        XCTAssertEqual(mockLogger.loggedMessages.count, 1)
        XCTAssertEqual(mockLogger.loggedMessages.first?.level, .warning)
    }

    func testLogErrorDispatches() {
        viewModel.logError(customText: "Error event")
        XCTAssertEqual(mockLogger.loggedMessages.count, 1)
        XCTAssertEqual(mockLogger.loggedMessages.first?.level, .error)
    }

    func testLogCustomDispatchesSelectedLevel() {
        viewModel.customMessage = "Custom fatal condition"
        viewModel.selectedLogLevel = .error

        viewModel.logCustom()

        XCTAssertEqual(mockLogger.loggedMessages.count, 1)
        XCTAssertEqual(mockLogger.loggedMessages.first?.level, .error)
        XCTAssertEqual(mockLogger.loggedMessages.first?.message, "Custom fatal condition")
    }

    func testMaskingDemonstrationDispatchesMessage() {
        viewModel.sampleBearerInput = "Bearer secret_abc_xyz"
        viewModel.sampleEmailInput = "test@internal.net"

        viewModel.demonstrateAutomaticMasking()

        XCTAssertEqual(mockLogger.loggedMessages.count, 1)
        XCTAssertEqual(mockLogger.loggedMessages.first?.level, .info)
        XCTAssertTrue(mockLogger.loggedMessages.first?.message.contains("Bearer secret_abc_xyz") == true)
        XCTAssertFalse(viewModel.dispatchedLogs.isEmpty)
    }

    func testClearDispatchedLogs() {
        viewModel.logInfo()
        viewModel.logError()
        XCTAssertEqual(viewModel.dispatchedLogs.count, 2)

        viewModel.clearDispatchedLogs()
        XCTAssertEqual(viewModel.dispatchedLogs.count, 0)
    }
}
