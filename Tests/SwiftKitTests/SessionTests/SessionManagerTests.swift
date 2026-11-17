import Foundation
import XCTest
@testable import SwiftKit

final class SessionManagerTests: XCTestCase {
    private let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
    private let storageKey = "com.swiftkit.tests.session"

    override func setUp() {
        super.setUp()
        SwiftKit.resetForTesting()
    }

    override func tearDown() {
        SwiftKit.resetForTesting()
        super.tearDown()
    }

    // MARK: - Initial State

    func testInitialStateIsUnauthenticated() {
        let (manager, _, _, _) = makeManager()

        XCTAssertFalse(manager.isAuthenticated)
        XCTAssertNil(manager.currentSession)
        XCTAssertEqual(manager.state, .unauthenticated)
    }

    // MARK: - Start Session

    func testStartSessionPersistsAndAuthenticates() throws {
        let (manager, _, storage, _) = makeManager()
        let session = makeSession(expiresAt: baseDate.addingTimeInterval(3600))

        try manager.startSession(session)

        XCTAssertTrue(manager.isAuthenticated)
        XCTAssertEqual(manager.currentSession, session)
        XCTAssertEqual(manager.state, .authenticated(session))
        XCTAssertEqual(try storage.codable(Session.self, forKey: storageKey), session)
    }

    func testStartSessionEmitsAuthenticatedEvent() throws {
        let (manager, _, _, _) = makeManager()
        let events = ThreadSafeBox<[SessionEvent]>([])
        manager.addObserver { event in events.mutate { $0.append(event) } }

        let session = makeSession(expiresAt: baseDate.addingTimeInterval(3600))
        try manager.startSession(session)

        XCTAssertEqual(events.current, [.authenticated(session)])
    }

    func testStartSessionRejectsExpiredSession() {
        let (manager, _, _, _) = makeManager()
        let expired = makeSession(expiresAt: baseDate.addingTimeInterval(-1))

        XCTAssertThrowsError(try manager.startSession(expired)) { error in
            XCTAssertEqual(error as? SessionError, .invalidExpiry)
        }
        XCTAssertFalse(manager.isAuthenticated)
    }

    func testStartSessionRejectsExpirationEqualToNow() {
        let (manager, _, _, _) = makeManager()
        let boundary = makeSession(expiresAt: baseDate)

        XCTAssertThrowsError(try manager.startSession(boundary)) { error in
            XCTAssertEqual(error as? SessionError, .invalidExpiry)
        }
    }

    // MARK: - Restore Session

    func testRestoreReturnsNilWhenNothingStored() throws {
        let (manager, _, _, _) = makeManager()

        XCTAssertNil(try manager.restoreSession())
        XCTAssertFalse(manager.isAuthenticated)
    }

    func testRestoreRoundTripAcrossManagers() throws {
        let (manager, logger, storage, _) = makeManager()
        let session = makeSession(expiresAt: baseDate.addingTimeInterval(3600))
        try manager.startSession(session)

        let restoredManager = SessionManager(
            secureStorage: storage,
            logger: logger,
            storageKey: storageKey,
            now: { self.baseDate }
        )

        let restored = try restoredManager.restoreSession()

        XCTAssertEqual(restored, session)
        XCTAssertEqual(restoredManager.currentSession, session)
    }

    func testRestoreMarksExpiredSessionAndEmitsExpired() throws {
        let clock = TestClock(baseDate)
        let (manager, logger, storage, _) = makeManager(clock: clock)
        try manager.startSession(makeSession(expiresAt: baseDate.addingTimeInterval(3600)))

        clock.advance(by: 7200)

        let restoredManager = SessionManager(
            secureStorage: storage,
            logger: logger,
            storageKey: storageKey,
            now: { clock.now }
        )
        let events = ThreadSafeBox<[SessionEvent]>([])
        restoredManager.addObserver { event in events.mutate { $0.append(event) } }

        let restored = try restoredManager.restoreSession()

        XCTAssertNil(restored)
        XCTAssertFalse(restoredManager.isAuthenticated)
        XCTAssertEqual(restoredManager.state, .expired)
        XCTAssertEqual(events.current, [.expired])
        XCTAssertTrue(storage.contains(storageKey))
    }

    func testRestoreThrowsDecodingFailedForCorruptData() throws {
        let (manager, _, storage, _) = makeManager()
        try storage.setData(Data("not-json".utf8), forKey: storageKey)

        XCTAssertThrowsError(try manager.restoreSession()) { error in
            XCTAssertEqual(error as? SessionError, .decodingFailed)
        }
    }

    // MARK: - Refresh Session (synchronous)

    func testRefreshPreservesUserIDAndEmitsRefreshed() throws {
        let (manager, _, storage, _) = makeManager()
        try manager.startSession(makeSession(expiresAt: baseDate.addingTimeInterval(3600), userID: "user-1"))

        let events = ThreadSafeBox<[SessionEvent]>([])
        manager.addObserver { event in events.mutate { $0.append(event) } }

        try manager.refreshSession(
            accessToken: "refreshed-access",
            refreshToken: "refreshed-refresh",
            expiresAt: baseDate.addingTimeInterval(7200)
        )

        let current = try XCTUnwrap(manager.currentSession)
        XCTAssertEqual(current.accessToken, "refreshed-access")
        XCTAssertEqual(current.refreshToken, "refreshed-refresh")
        XCTAssertEqual(current.userID, "user-1")
        XCTAssertEqual(events.current, [.refreshed(current)])
        XCTAssertEqual(try storage.codable(Session.self, forKey: storageKey).accessToken, "refreshed-access")
    }

    func testRefreshWithoutActiveSessionThrows() {
        let (manager, _, _, _) = makeManager()

        XCTAssertThrowsError(
            try manager.refreshSession(
                accessToken: "a",
                refreshToken: nil,
                expiresAt: baseDate.addingTimeInterval(3600)
            )
        ) { error in
            XCTAssertEqual(error as? SessionError, .noActiveSession)
        }
    }

    func testRefreshRejectsExpiredExpiration() throws {
        let (manager, _, _, _) = makeManager()
        try manager.startSession(makeSession(expiresAt: baseDate.addingTimeInterval(3600)))

        XCTAssertThrowsError(
            try manager.refreshSession(accessToken: "a", refreshToken: nil, expiresAt: baseDate)
        ) { error in
            XCTAssertEqual(error as? SessionError, .invalidExpiry)
        }
    }

    // MARK: - Refresh Session (asynchronous)

    func testAsyncRefreshRenewsSessionAndEmitsRefreshed() async throws {
        let renewed = SessionTokenRefresh(
            accessToken: "async-access",
            refreshToken: "async-refresh",
            expiresAt: baseDate.addingTimeInterval(7200)
        )
        let handler = MockSessionTokenRefreshHandler(behavior: .success(renewed))
        let (manager, _, storage, _) = makeManager(refreshHandler: handler)
        try manager.startSession(makeSession(expiresAt: baseDate.addingTimeInterval(3600), userID: "user-1"))

        let events = ThreadSafeBox<[SessionEvent]>([])
        manager.addObserver { event in events.mutate { $0.append(event) } }

        let refreshed = try await manager.refreshSession()

        XCTAssertEqual(refreshed.accessToken, "async-access")
        XCTAssertEqual(refreshed.refreshToken, "async-refresh")
        XCTAssertEqual(refreshed.userID, "user-1")
        XCTAssertEqual(manager.state, .authenticated(refreshed))
        XCTAssertEqual(events.current, [.refreshed(refreshed)])
        XCTAssertEqual(try storage.codable(Session.self, forKey: storageKey).accessToken, "async-access")
    }

    func testAsyncRefreshFromExpiredSessionSucceeds() async throws {
        let clock = TestClock(baseDate)
        let renewed = SessionTokenRefresh(accessToken: "renewed", expiresAt: baseDate.addingTimeInterval(10800))
        let handler = MockSessionTokenRefreshHandler(behavior: .success(renewed))
        let (manager, _, _, _) = makeManager(clock: clock, refreshHandler: handler)
        try manager.startSession(makeSession(expiresAt: baseDate.addingTimeInterval(3600)))

        clock.advance(by: 7200)
        manager.validateExpiry()
        XCTAssertEqual(manager.state, .expired)

        let refreshed = try await manager.refreshSession()

        XCTAssertEqual(refreshed.accessToken, "renewed")
        XCTAssertEqual(manager.state, .authenticated(refreshed))
    }

    func testAsyncRefreshWithoutSessionThrowsNoActiveSession() async {
        let handler = MockSessionTokenRefreshHandler(
            behavior: .success(SessionTokenRefresh(accessToken: "x", expiresAt: baseDate.addingTimeInterval(3600)))
        )
        let (manager, _, _, _) = makeManager(refreshHandler: handler)

        await assertRefreshThrows(manager, expected: .noActiveSession)
    }

    func testAsyncRefreshWithoutRefreshTokenThrowsMissingRefreshToken() async throws {
        let handler = MockSessionTokenRefreshHandler(
            behavior: .success(SessionTokenRefresh(accessToken: "x", expiresAt: baseDate.addingTimeInterval(3600)))
        )
        let (manager, _, _, _) = makeManager(refreshHandler: handler)
        try manager.startSession(
            Session(accessToken: "access", refreshToken: nil, expiresAt: baseDate.addingTimeInterval(3600))
        )

        await assertRefreshThrows(manager, expected: .missingRefreshToken)
    }

    func testAsyncRefreshWithoutHandlerThrowsHandlerUnavailable() async throws {
        let (manager, _, _, _) = makeManager()
        try manager.startSession(makeSession(expiresAt: baseDate.addingTimeInterval(3600)))

        await assertRefreshThrows(manager, expected: .refreshHandlerUnavailable)
    }

    func testAsyncRefreshOfflineThrowsOffline() async throws {
        let connectivity = MockConnectivityMonitor(status: .disconnected)
        let handler = MockSessionTokenRefreshHandler(
            behavior: .success(SessionTokenRefresh(accessToken: "x", expiresAt: baseDate.addingTimeInterval(3600)))
        )
        let (manager, _, _, _) = makeManager(connectivity: connectivity, refreshHandler: handler)
        try manager.startSession(makeSession(expiresAt: baseDate.addingTimeInterval(3600)))

        await assertRefreshThrows(manager, expected: .offline)
    }

    func testAsyncRefreshHandlerFailureThrowsRefreshFailed() async throws {
        let handler = MockSessionTokenRefreshHandler(behavior: .failure(URLError(.badServerResponse)))
        let (manager, _, _, _) = makeManager(refreshHandler: handler)
        try manager.startSession(makeSession(expiresAt: baseDate.addingTimeInterval(3600)))

        await assertRefreshThrows(manager, expected: .refreshFailed)
    }

    func testAsyncRefreshCancellationThrowsRefreshCancelled() async throws {
        let handler = MockSessionTokenRefreshHandler(behavior: .failure(CancellationError()))
        let (manager, _, _, _) = makeManager(refreshHandler: handler)
        try manager.startSession(makeSession(expiresAt: baseDate.addingTimeInterval(3600)))

        await assertRefreshThrows(manager, expected: .refreshCancelled)
    }

    func testLogoutCancelsInFlightRefresh() async throws {
        let handler = ControllableRefreshHandler()
        let (manager, _, storage, _) = makeManager(refreshHandler: handler)
        try manager.startSession(makeSession(expiresAt: baseDate.addingTimeInterval(3600)))

        let refresh = Task { try await manager.refreshSession() }
        while !handler.hasPending { await Task.yield() }

        try manager.logout()
        handler.resume(
            returning: SessionTokenRefresh(accessToken: "late", expiresAt: baseDate.addingTimeInterval(7200))
        )

        do {
            _ = try await refresh.value
            XCTFail("Expected refreshCancelled after logout.")
        } catch {
            XCTAssertEqual(error as? SessionError, .refreshCancelled)
        }
        XCTAssertFalse(manager.isAuthenticated)
        XCTAssertFalse(storage.contains(storageKey))
    }

    // MARK: - Logout

    func testLogoutClearsStorageAndEmitsLoggedOut() throws {
        let (manager, _, storage, _) = makeManager()
        try manager.startSession(makeSession(expiresAt: baseDate.addingTimeInterval(3600)))

        let events = ThreadSafeBox<[SessionEvent]>([])
        manager.addObserver { event in events.mutate { $0.append(event) } }

        try manager.logout()

        XCTAssertFalse(manager.isAuthenticated)
        XCTAssertNil(manager.currentSession)
        XCTAssertFalse(storage.contains(storageKey))
        XCTAssertEqual(events.current, [.loggedOut])
    }

    func testLogoutWhenNoSessionIsTolerant() {
        let (manager, _, _, _) = makeManager()
        let events = ThreadSafeBox<[SessionEvent]>([])
        manager.addObserver { event in events.mutate { $0.append(event) } }

        XCTAssertNoThrow(try manager.logout())
        XCTAssertEqual(events.current, [.loggedOut])
    }

    func testLogoutThrowsStorageFailureWhenClearFails() throws {
        let (manager, _, _, client) = makeManager()
        try manager.startSession(makeSession(expiresAt: baseDate.addingTimeInterval(3600)))
        client.failOnDelete = .deleteFailed(status: -1)

        XCTAssertThrowsError(try manager.logout()) { error in
            XCTAssertEqual(error as? SessionError, .storageFailure)
        }
    }

    // MARK: - Expiry Validation

    func testValidateExpiryMarksSessionExpired() throws {
        let clock = TestClock(baseDate)
        let (manager, _, storage, _) = makeManager(clock: clock)
        try manager.startSession(makeSession(expiresAt: baseDate.addingTimeInterval(3600)))

        let events = ThreadSafeBox<[SessionEvent]>([])
        manager.addObserver { event in events.mutate { $0.append(event) } }

        clock.advance(by: 7200)
        manager.validateExpiry()

        XCTAssertFalse(manager.isAuthenticated)
        XCTAssertNil(manager.currentSession)
        XCTAssertEqual(manager.state, .expired)
        XCTAssertTrue(storage.contains(storageKey))
        XCTAssertEqual(events.current, [.expired])
    }

    func testValidateExpiryIsNoOpForValidSession() throws {
        let (manager, _, _, _) = makeManager()
        try manager.startSession(makeSession(expiresAt: baseDate.addingTimeInterval(3600)))

        let events = ThreadSafeBox<[SessionEvent]>([])
        manager.addObserver { event in events.mutate { $0.append(event) } }

        manager.validateExpiry()

        XCTAssertTrue(manager.isAuthenticated)
        XCTAssertTrue(events.current.isEmpty)
    }

    func testValidateExpiryIsIdempotent() throws {
        let clock = TestClock(baseDate)
        let (manager, _, _, _) = makeManager(clock: clock)
        try manager.startSession(makeSession(expiresAt: baseDate.addingTimeInterval(3600)))

        let events = ThreadSafeBox<[SessionEvent]>([])
        manager.addObserver { event in events.mutate { $0.append(event) } }

        clock.advance(by: 7200)
        manager.validateExpiry()
        manager.validateExpiry()

        XCTAssertEqual(events.current, [.expired])
    }

    // MARK: - Duplicate State Suppression

    func testRepeatedLogoutEmitsSingleEvent() throws {
        let (manager, _, _, _) = makeManager()
        try manager.startSession(makeSession(expiresAt: baseDate.addingTimeInterval(3600)))

        let events = ThreadSafeBox<[SessionEvent]>([])
        manager.addObserver { event in events.mutate { $0.append(event) } }

        try manager.logout()
        try manager.logout()

        XCTAssertEqual(events.current, [.loggedOut])
    }

    func testRestoringNothingAfterLogoutEmitsNoEvent() throws {
        let (manager, _, _, _) = makeManager()
        let events = ThreadSafeBox<[SessionEvent]>([])
        manager.addObserver { event in events.mutate { $0.append(event) } }

        XCTAssertNil(try manager.restoreSession())
        XCTAssertTrue(events.current.isEmpty)
    }

    // MARK: - Unauthorized

    func testHandleUnauthorizedClearsSessionAndEmitsUnauthorized() throws {
        let (manager, _, storage, _) = makeManager()
        try manager.startSession(makeSession(expiresAt: baseDate.addingTimeInterval(3600)))

        let events = ThreadSafeBox<[SessionEvent]>([])
        manager.addObserver { event in events.mutate { $0.append(event) } }

        manager.handleUnauthorized()

        XCTAssertFalse(manager.isAuthenticated)
        XCTAssertFalse(storage.contains(storageKey))
        XCTAssertEqual(events.current, [.unauthorized])
    }

    // MARK: - Observers

    func testObserverReceivesOnlyFutureEvents() throws {
        let (manager, _, _, _) = makeManager()
        let events = ThreadSafeBox<[SessionEvent]>([])
        manager.addObserver { event in events.mutate { $0.append(event) } }

        XCTAssertTrue(events.current.isEmpty)

        try manager.startSession(makeSession(expiresAt: baseDate.addingTimeInterval(3600)))

        XCTAssertEqual(events.current.count, 1)
    }

    func testRemoveObserverStopsDelivery() throws {
        let (manager, _, _, _) = makeManager()
        let events = ThreadSafeBox<[SessionEvent]>([])
        let token = manager.addObserver { event in events.mutate { $0.append(event) } }

        manager.removeObserver(token)
        try manager.startSession(makeSession(expiresAt: baseDate.addingTimeInterval(3600)))

        XCTAssertTrue(events.current.isEmpty)
    }

    func testObserverCanCallBackIntoManagerWithoutDeadlock() throws {
        let (manager, _, _, _) = makeManager()
        let observedStates = ThreadSafeBox<[Bool]>([])
        manager.addObserver { _ in
            observedStates.mutate { $0.append(manager.isAuthenticated) }
        }

        try manager.startSession(makeSession(expiresAt: baseDate.addingTimeInterval(3600)))

        XCTAssertEqual(observedStates.current, [true])
    }

    // MARK: - Concurrency

    func testConcurrentLifecycleOperationsRemainConsistent() throws {
        let (manager, _, storage, _) = makeManager()
        try manager.startSession(makeSession(expiresAt: baseDate.addingTimeInterval(3600)))

        DispatchQueue.concurrentPerform(iterations: 50) { index in
            if index.isMultiple(of: 2) {
                try? manager.startSession(self.makeSession(expiresAt: self.baseDate.addingTimeInterval(3600)))
            } else {
                try? manager.logout()
            }
        }

        XCTAssertEqual(manager.isAuthenticated, manager.currentSession != nil)
        XCTAssertEqual(storage.contains(storageKey), manager.currentSession != nil)
    }

    // MARK: - Storage Failures

    func testPersistenceFailureThrowsStorageFailure() {
        let (manager, _, _, client) = makeManager()
        client.failOnWrite = .writeFailed(status: -1)

        XCTAssertThrowsError(try manager.startSession(makeSession(expiresAt: baseDate.addingTimeInterval(3600)))) { error in
            XCTAssertEqual(error as? SessionError, .storageFailure)
        }
        XCTAssertFalse(manager.isAuthenticated)
    }

    // MARK: - Security

    func testAccessTokenIsNotLoggedInClearText() throws {
        let (manager, logger, _, _) = makeManager()
        let secret = "super-secret-access-token"

        try manager.startSession(
            Session(accessToken: secret, refreshToken: nil, expiresAt: baseDate.addingTimeInterval(3600))
        )

        let combined = logger.recordedEntries.map(\.message).joined(separator: " ")
        XCTAssertFalse(combined.contains(secret))
    }

    // MARK: - Integration Wiring

    func testContainerWiresSessionManager() {
        let container = SDKDependencyContainer(configuration: SwiftKitConfiguration())

        XCTAssertTrue(container.session is SessionManager)
        XCTAssertFalse(container.session.isAuthenticated)
    }

    func testFacadeExposesSessionManager() throws {
        try SwiftKit.initialize(configuration: SwiftKitConfiguration(subsystem: "com.swiftkit.tests.session"))

        XCTAssertTrue(SwiftKit.shared.session is SessionManager)
    }

    // MARK: - Helpers

    private func assertRefreshThrows(
        _ manager: SessionManager,
        expected: SessionError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await manager.refreshSession()
            XCTFail("Expected \(expected) to be thrown.", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? SessionError, expected, file: file, line: line)
        }
    }

    private func makeManager(
        clock: TestClock? = nil,
        connectivity: ConnectivityMonitorProtocol? = nil,
        refreshHandler: SessionTokenRefreshHandler? = nil
    ) -> (SessionManager, MockLogger, KeychainStorage, InMemoryKeychainClient) {
        let resolvedClock = clock ?? TestClock(baseDate)
        let logger = MockLogger()
        let client = InMemoryKeychainClient()
        let storage = KeychainStorage(
            service: "com.swiftkit.tests.session.service",
            accessibility: .afterFirstUnlockThisDeviceOnly,
            client: client,
            logger: logger
        )
        let manager = SessionManager(
            secureStorage: storage,
            logger: logger,
            connectivity: connectivity,
            refreshHandler: refreshHandler,
            storageKey: storageKey,
            now: { resolvedClock.now }
        )
        return (manager, logger, storage, client)
    }

    private func makeSession(
        expiresAt: Date,
        userID: String? = "user-1",
        accessToken: String = "access-token"
    ) -> Session {
        Session(
            accessToken: accessToken,
            refreshToken: "refresh-token",
            expiresAt: expiresAt,
            userID: userID
        )
    }
}

/// Mutable clock used to drive deterministic expiry behavior in tests.
private final class TestClock: @unchecked Sendable {
    private let box: ThreadSafeBox<Date>

    internal init(_ date: Date) {
        self.box = ThreadSafeBox(date)
    }

    internal var now: Date {
        box.current
    }

    internal func advance(by interval: TimeInterval) {
        box.mutate { $0 = $0.addingTimeInterval(interval) }
    }
}

/// Connectivity monitor stub returning a fixed status.
private final class MockConnectivityMonitor: ConnectivityMonitorProtocol, @unchecked Sendable {
    private let box: ThreadSafeBox<ConnectivityStatus>

    internal init(status: ConnectivityStatus = .unknown) {
        self.box = ThreadSafeBox(status)
    }

    internal var currentStatus: ConnectivityStatus {
        box.current
    }

    internal var isMonitoring: Bool {
        false
    }

    internal func start() {}

    internal func stop() {}

    @discardableResult
    internal func addObserver(
        _ observer: @escaping @Sendable (ConnectivityStatus) -> Void
    ) -> ConnectivityObservationToken {
        ConnectivityObservationToken()
    }

    internal func removeObserver(_ token: ConnectivityObservationToken) {}
}

/// Token-refresh handler stub with a configurable behavior.
private final class MockSessionTokenRefreshHandler: SessionTokenRefreshHandler, @unchecked Sendable {
    internal enum Behavior: Sendable {
        case success(SessionTokenRefresh)
        case failure(Error)
    }

    private let box: ThreadSafeBox<Behavior>

    internal init(behavior: Behavior) {
        self.box = ThreadSafeBox(behavior)
    }

    internal func refresh(using refreshToken: String) async throws -> SessionTokenRefresh {
        switch box.current {
        case .success(let value):
            return value
        case .failure(let error):
            throw error
        }
    }
}

/// Token-refresh handler that suspends until the test resumes it.
private final class ControllableRefreshHandler: SessionTokenRefreshHandler, @unchecked Sendable {
    private let box = ThreadSafeBox<CheckedContinuation<SessionTokenRefresh, Error>?>(nil)

    internal var hasPending: Bool {
        box.current != nil
    }

    internal func refresh(using refreshToken: String) async throws -> SessionTokenRefresh {
        try await withCheckedThrowingContinuation { continuation in
            box.write(continuation)
        }
    }

    internal func resume(returning value: SessionTokenRefresh) {
        box.mutate { continuation in
            continuation?.resume(returning: value)
            continuation = nil
        }
    }
}
