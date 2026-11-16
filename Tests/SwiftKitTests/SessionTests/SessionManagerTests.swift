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

    func testRestoreClearsExpiredSessionAndEmitsExpired() throws {
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
        XCTAssertEqual(events.current, [.expired])
        XCTAssertFalse(storage.contains(storageKey))
    }

    func testRestoreThrowsDecodingFailedForCorruptData() throws {
        let (manager, _, storage, _) = makeManager()
        try storage.setData(Data("not-json".utf8), forKey: storageKey)

        XCTAssertThrowsError(try manager.restoreSession()) { error in
            XCTAssertEqual(error as? SessionError, .decodingFailed)
        }
    }

    // MARK: - Refresh Session

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

    func testValidateExpiryClearsExpiredSession() throws {
        let clock = TestClock(baseDate)
        let (manager, _, storage, _) = makeManager(clock: clock)
        try manager.startSession(makeSession(expiresAt: baseDate.addingTimeInterval(3600)))

        let events = ThreadSafeBox<[SessionEvent]>([])
        manager.addObserver { event in events.mutate { $0.append(event) } }

        clock.advance(by: 7200)
        manager.validateExpiry()

        XCTAssertFalse(manager.isAuthenticated)
        XCTAssertFalse(storage.contains(storageKey))
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

    private func makeManager(
        clock: TestClock? = nil
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
