import XCTest
import SwiftKit
@testable import SampleApp

@MainActor
final class SessionViewModelTests: XCTestCase {
    private var mockSession: MockSessionManager!
    private var mockLogger: MockLogger!
    private var viewModel: SessionViewModel!

    override func setUp() {
        super.setUp()
        Self.ensureSDKInitialized()
        mockSession = MockSessionManager()
        mockLogger = MockLogger()
        viewModel = SessionViewModel(session: mockSession, logger: mockLogger)
    }

    override func tearDown() {
        viewModel = nil
        mockSession = nil
        mockLogger = nil
        super.tearDown()
    }

    func testStartSessionUpdatesStateAndRecordsObserverEvent() async throws {
        viewModel.accessTokenInput = "test_access_token"
        viewModel.lifetimeSeconds = 600

        viewModel.startSession()

        XCTAssertEqual(mockSession.startSessionCallCount, 1)
        XCTAssertTrue(viewModel.isAuthenticated)
        XCTAssertEqual(viewModel.stateTitle, "Authenticated")
        XCTAssertEqual(viewModel.maskedAccessToken, "Bearer [REDACTED]")
        XCTAssertEqual(viewModel.userID, "sample-user-42")

        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(viewModel.events.first?.title, "Authenticated")
    }

    func testRestoreSessionLoadsPersistedSession() {
        mockSession.restoredSession = Session(
            accessToken: "restored_token",
            refreshToken: "restored_refresh",
            expiresAt: Date().addingTimeInterval(3600),
            userID: "restored-user"
        )

        viewModel.restoreSession()

        XCTAssertEqual(mockSession.restoreSessionCallCount, 1)
        XCTAssertTrue(viewModel.isAuthenticated)
        XCTAssertEqual(viewModel.userID, "restored-user")
        XCTAssertTrue(viewModel.statusMessage.contains("Restored"))
    }

    func testValidateExpiryTransitionsAuthenticatedSessionToExpired() {
        try? mockSession.startSession(
            Session(
                accessToken: "expired_token",
                refreshToken: "expired_refresh",
                expiresAt: Date().addingTimeInterval(-60),
                userID: "expired-user"
            )
        )

        viewModel.validateExpiry()

        XCTAssertEqual(mockSession.validateExpiryCallCount, 1)
        XCTAssertFalse(viewModel.isAuthenticated)
        XCTAssertEqual(viewModel.stateTitle, "Expired")
        XCTAssertTrue(viewModel.expiryText.contains("Expired"))
    }

    func testSynchronousRefreshKeepsSessionAuthenticated() {
        try? mockSession.startSession(
            Session(
                accessToken: "old_token",
                refreshToken: "old_refresh",
                expiresAt: Date().addingTimeInterval(3600),
                userID: "same-user"
            )
        )

        viewModel.refreshSynchronously()

        XCTAssertEqual(mockSession.syncRefreshCallCount, 1)
        XCTAssertTrue(viewModel.isAuthenticated)
        XCTAssertTrue(viewModel.statusMessage.contains("Synchronous refresh"))
    }

    func testAsynchronousRefreshUsesConfiguredHandler() async {
        try? mockSession.startSession(
            Session(
                accessToken: "old_token",
                refreshToken: "old_refresh",
                expiresAt: Date().addingTimeInterval(3600),
                userID: "same-user"
            )
        )

        await viewModel.refreshAsynchronously()

        XCTAssertEqual(mockSession.asyncRefreshCallCount, 1)
        XCTAssertTrue(viewModel.isAuthenticated)
        XCTAssertTrue(viewModel.statusMessage.contains("Async refresh returned"))
    }

    func testAsynchronousRefreshFailureIsReported() async {
        await viewModel.refreshAsynchronously()

        XCTAssertTrue(viewModel.isErrorMessage)
        XCTAssertTrue(viewModel.statusMessage.contains("Async refresh failed"))
    }

    func testHandleUnauthorizedClearsSession() {
        try? mockSession.startSession(
            Session(accessToken: "token", refreshToken: "refresh", expiresAt: Date().addingTimeInterval(3600))
        )

        viewModel.handleUnauthorized()

        XCTAssertEqual(mockSession.handleUnauthorizedCallCount, 1)
        XCTAssertEqual(viewModel.stateTitle, "Unauthenticated")
        XCTAssertTrue(viewModel.statusMessage.contains("401"))
    }

    func testLogoutClearsSession() {
        try? mockSession.startSession(
            Session(accessToken: "token", refreshToken: "refresh", expiresAt: Date().addingTimeInterval(3600))
        )

        viewModel.logout()

        XCTAssertEqual(mockSession.logoutCallCount, 1)
        XCTAssertEqual(viewModel.stateTitle, "Unauthenticated")
        XCTAssertFalse(viewModel.isAuthenticated)
    }

    func testClearEventsRemovesRecordedTransitions() async throws {
        viewModel.startSession()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(viewModel.events.isEmpty)

        viewModel.clearEvents()

        XCTAssertTrue(viewModel.events.isEmpty)
    }

    private static func ensureSDKInitialized() {
        guard !SwiftKit.isInitialized else { return }
        let configuration = SwiftKitConfiguration(
            subsystem: "com.swiftkit.sampleapp.tests",
            category: "SessionViewModelTests",
            keychainService: "com.swiftkit.sampleapp.tests.storage"
        )
        try? SwiftKit.initialize(configuration: configuration)
    }
}
