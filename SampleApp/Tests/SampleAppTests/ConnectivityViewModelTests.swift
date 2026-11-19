import XCTest
import SwiftKit
@testable import SampleApp

@MainActor
final class ConnectivityViewModelTests: XCTestCase {
    private var mockConnectivity: MockConnectivityMonitor!
    private var mockLogger: MockLogger!
    private var viewModel: ConnectivityViewModel!

    override func setUp() {
        super.setUp()
        mockConnectivity = MockConnectivityMonitor(initialStatus: .connected)
        mockLogger = MockLogger()
        viewModel = ConnectivityViewModel(connectivity: mockConnectivity, logger: mockLogger)
    }

    override func tearDown() {
        viewModel = nil
        mockConnectivity = nil
        mockLogger = nil
        super.tearDown()
    }

    func testInitialState() {
        XCTAssertEqual(viewModel.currentStatus, .connected)
        XCTAssertFalse(viewModel.isMonitoring)
        XCTAssertFalse(viewModel.hasActiveObserver)
    }

    func testStartAndStopMonitoring() {
        viewModel.startMonitoring()
        XCTAssertTrue(viewModel.isMonitoring)
        XCTAssertTrue(viewModel.hasActiveObserver)

        viewModel.stopMonitoring()
        XCTAssertFalse(viewModel.isMonitoring)
        XCTAssertFalse(viewModel.hasActiveObserver)
    }

    func testObserverReceivesStatusTransitions() async throws {
        viewModel.startMonitoring()

        // Wait for registration snapshot to be processed
        try await Task.sleep(nanoseconds: 50_000_000)

        // Simulate status change to disconnected
        mockConnectivity.simulateStatusChange(.disconnected)

        // Wait for async MainActor dispatch in observer
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(viewModel.currentStatus, .disconnected)
        XCTAssertFalse(viewModel.eventLog.isEmpty)
        XCTAssertEqual(viewModel.eventLog.first?.status, .disconnected)
    }

    func testClearEventLog() {
        viewModel.eventLog = [
            ConnectivityEvent(status: .connected),
            ConnectivityEvent(status: .disconnected)
        ]
        XCTAssertEqual(viewModel.eventLog.count, 2)

        viewModel.clearEventLog()
        XCTAssertEqual(viewModel.eventLog.count, 0)
    }
}
