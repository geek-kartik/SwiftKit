import Foundation
import SwiftKit
@testable import SampleApp

/// In-memory implementation of `SecureStorageProtocol` for SampleApp unit tests.
public final class MockSecureStorage: SecureStorageProtocol, @unchecked Sendable {
    private var storage: [String: Data] = [:]
    private let lock = NSLock()

    public var shouldThrowOnWrite: Bool = false
    public var shouldThrowOnRead: Bool = false

    public init() {}

    public func setData(_ data: Data, forKey key: String) throws {
        lock.lock()
        defer { lock.unlock() }

        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SecureStorageError.invalidKey
        }
        if shouldThrowOnWrite {
            throw SecureStorageError.writeFailed(status: -50)
        }
        storage[key] = data
    }

    public func data(forKey key: String) throws -> Data {
        lock.lock()
        defer { lock.unlock() }

        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SecureStorageError.invalidKey
        }
        if shouldThrowOnRead {
            throw SecureStorageError.readFailed(status: -50)
        }
        guard let value = storage[key] else {
            throw SecureStorageError.itemNotFound(key: key)
        }
        return value
    }

    public func contains(_ key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return storage[key] != nil
    }

    public func remove(forKey key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        storage.removeValue(forKey: key)
    }

    public func removeAll() throws {
        lock.lock()
        defer { lock.unlock() }
        storage.removeAll()
    }
}

/// Mock implementation of `DeviceInfoProtocol` for SampleApp unit tests.
public final class MockDeviceInfo: DeviceInfoProtocol, @unchecked Sendable {
    public var deviceModel: String = "iPhone15,2"
    public var osVersion: String = "17.4"
    public var appVersion: String = "1.2.0"
    public var buildNumber: String = "42"
    public var bundleIdentifier: String = "com.swiftkit.sampleapp"
    public var appName: String = "SampleApp"
    public var isSimulator: Bool = true
    public var isDebugBuild: Bool = true

    public init() {}
}

/// Mock implementation of `ConnectivityMonitorProtocol` for SampleApp unit tests.
public final class MockConnectivityMonitor: ConnectivityMonitorProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var observers: [ConnectivityObservationToken: @Sendable (ConnectivityStatus) -> Void] = [:]

    public var currentStatus: ConnectivityStatus = .unknown
    public var isMonitoring: Bool = false

    public init(initialStatus: ConnectivityStatus = .unknown) {
        self.currentStatus = initialStatus
    }

    public func start() {
        lock.lock()
        defer { lock.unlock() }
        isMonitoring = true
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        isMonitoring = false
    }

    public func addObserver(_ observer: @escaping @Sendable (ConnectivityStatus) -> Void) -> ConnectivityObservationToken {
        lock.lock()
        let token = ConnectivityObservationToken()
        observers[token] = observer
        let snapshot = currentStatus
        lock.unlock()

        observer(snapshot)
        return token
    }

    public func removeObserver(_ token: ConnectivityObservationToken) {
        lock.lock()
        defer { lock.unlock() }
        observers.removeValue(forKey: token)
    }

    /// Simulates a network transition event.
    public func simulateStatusChange(_ newStatus: ConnectivityStatus) {
        lock.lock()
        currentStatus = newStatus
        let currentObservers = Array(observers.values)
        lock.unlock()

        for observer in currentObservers {
            observer(newStatus)
        }
    }
}

/// Mock implementation of `LoggerProtocol` recording calls for verification.
public final class MockLogger: LoggerProtocol, @unchecked Sendable {
    private let lock = NSLock()
    public var loggedMessages: [(level: LogLevel, message: String)] = []

    public init() {}

    public func log(_ message: String, level: LogLevel, file: String, function: String, line: Int) {
        lock.lock()
        defer { lock.unlock() }
        loggedMessages.append((level, message))
    }
}

public final class MockSessionManager: SessionManagerProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private let tokenSource: SessionManagerProtocol
    private var storedState: SessionState = .unauthenticated
    private var observers: [SessionObservationToken: @Sendable (SessionEvent) -> Void] = [:]
    private var startCount = 0
    private var restoreCount = 0
    private var syncRefreshCount = 0
    private var asyncRefreshCount = 0
    private var logoutCount = 0
    private var validateCount = 0
    private var unauthorizedCount = 0
    private var lastObservedEvent: SessionEvent?

    public var restoredSession: Session?
    public var restoreError: Error?
    public var asyncRefreshError: Error?
    public var asyncRefreshDelay: TimeInterval = 0
    public var refreshedAccessToken = "refreshed_access_token"
    public var refreshedRefreshToken = "refreshed_refresh_token"

    public init(tokenSource: SessionManagerProtocol? = nil) {
        self.tokenSource = tokenSource ?? SDKService.shared.session
    }

    public var state: SessionState {
        lock.lock()
        defer { lock.unlock() }
        return storedState
    }

    public var currentSession: Session? {
        state.session
    }

    public var isAuthenticated: Bool {
        state.isAuthenticated
    }

    public var startSessionCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return startCount
    }

    public var restoreSessionCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return restoreCount
    }

    public var syncRefreshCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return syncRefreshCount
    }

    public var asyncRefreshCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return asyncRefreshCount
    }

    public var logoutCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return logoutCount
    }

    public var validateExpiryCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return validateCount
    }

    public var handleUnauthorizedCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return unauthorizedCount
    }

    public var lastEvent: SessionEvent? {
        lock.lock()
        defer { lock.unlock() }
        return lastObservedEvent
    }

    public var observerCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return observers.count
    }

    public func startSession(_ session: Session) throws {
        lock.lock()
        startCount += 1
        storedState = .authenticated(session)
        let callbacks = Array(observers.values)
        lock.unlock()

        notify(callbacks, of: .authenticated(session))
    }

    public func restoreSession() throws -> Session? {
        lock.lock()
        restoreCount += 1
        if let restoreError {
            lock.unlock()
            throw restoreError
        }

        let restored = restoredSession
        let nextState: SessionState
        if let restored {
            nextState = restored.isExpired(at: Date()) ? .expired : .authenticated(restored)
        } else {
            nextState = storedState
        }
        storedState = nextState
        let callbacks = Array(observers.values)
        lock.unlock()

        if case .authenticated(let session) = nextState {
            notify(callbacks, of: .authenticated(session))
        }
        return restored
    }

    public func refreshSession(accessToken: String, refreshToken: String?, expiresAt: Date) throws {
        lock.lock()
        guard let current = storedState.session else {
            lock.unlock()
            throw SessionError.noActiveSession
        }
        guard expiresAt > Date() else {
            lock.unlock()
            throw SessionError.invalidExpiry
        }

        let refreshed = Session(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            userID: current.userID
        )
        syncRefreshCount += 1
        storedState = .authenticated(refreshed)
        let callbacks = Array(observers.values)
        lock.unlock()

        notify(callbacks, of: .refreshed(refreshed))
    }

    public func refreshSession() async throws -> Session {
        let delay = asyncRefreshDelay
        if delay > 0 {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        let (refreshed, callbacks) = try prepareAsyncRefresh()
        notify(callbacks, of: .refreshed(refreshed))
        return refreshed
    }

    private func prepareAsyncRefresh() throws -> (Session, [@Sendable (SessionEvent) -> Void]) {
        lock.lock()
        defer { lock.unlock() }

        asyncRefreshCount += 1
        if let asyncRefreshError {
            throw asyncRefreshError
        }
        guard let current = storedState.session else {
            throw SessionError.noActiveSession
        }

        let refreshed = Session(
            accessToken: refreshedAccessToken,
            refreshToken: refreshedRefreshToken,
            expiresAt: Date().addingTimeInterval(3600),
            userID: current.userID
        )
        storedState = .authenticated(refreshed)
        return (refreshed, Array(observers.values))
    }

    public func logout() throws {
        lock.lock()
        logoutCount += 1
        storedState = .unauthenticated
        let callbacks = Array(observers.values)
        lock.unlock()

        notify(callbacks, of: .loggedOut)
    }

    public func validateExpiry() {
        lock.lock()
        validateCount += 1
        guard case .authenticated(let session) = storedState, session.isExpired(at: Date()) else {
            lock.unlock()
            return
        }

        storedState = .expired
        let callbacks = Array(observers.values)
        lock.unlock()

        notify(callbacks, of: .expired)
    }

    public func handleUnauthorized() {
        lock.lock()
        unauthorizedCount += 1
        storedState = .unauthenticated
        let callbacks = Array(observers.values)
        lock.unlock()

        notify(callbacks, of: .unauthorized)
    }

    public func addObserver(_ observer: @escaping @Sendable (SessionEvent) -> Void) -> SessionObservationToken {
        let token = tokenSource.addObserver { _ in }
        lock.lock()
        observers[token] = observer
        lock.unlock()
        return token
    }

    public func removeObserver(_ token: SessionObservationToken) {
        tokenSource.removeObserver(token)
        lock.lock()
        observers.removeValue(forKey: token)
        lock.unlock()
    }

    private func notify(_ callbacks: [@Sendable (SessionEvent) -> Void], of event: SessionEvent) {
        lock.lock()
        lastObservedEvent = event
        lock.unlock()

        for callback in callbacks {
            callback(event)
        }
    }
}

public final class MockNetworkClient: NetworkClientProtocol, @unchecked Sendable {
    public let configuration: NetworkConfiguration

    private let lock = NSLock()
    private var recordedRequests: [NetworkRequest] = []
    private var responseHandler: (@Sendable (NetworkRequest) async throws -> NetworkResponse)?

    public init(
        configuration: NetworkConfiguration = .default,
        responseHandler: (@Sendable (NetworkRequest) async throws -> NetworkResponse)? = nil
    ) {
        self.configuration = configuration
        self.responseHandler = responseHandler
    }

    public var sentRequests: [NetworkRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recordedRequests
    }

    public var callCount: Int {
        sentRequests.count
    }

    public func send(_ request: NetworkRequest) async throws -> NetworkResponse {
        if let handler = recordAndResolveHandler(for: request) {
            return try await handler(request)
        }

        return Self.successResponse()
    }

    private func recordAndResolveHandler(
        for request: NetworkRequest
    ) -> (@Sendable (NetworkRequest) async throws -> NetworkResponse)? {
        lock.lock()
        defer { lock.unlock() }
        recordedRequests.append(request)
        return responseHandler
    }

    public static func successResponse(
        statusCode: Int = 200,
        data: Data = Data(#"{"status":"ok","message":"Mock response"}"#.utf8)
    ) -> NetworkResponse {
        NetworkResponse(statusCode: statusCode, headers: [:], data: data)
    }
}

public final class MockSessionTokenRefreshHandler: SessionTokenRefreshHandler, @unchecked Sendable {
    private let lock = NSLock()
    private var receivedTokens: [String] = []

    public var result: SessionTokenRefresh
    public var error: Error?

    public init(
        result: SessionTokenRefresh = SessionTokenRefresh(
            accessToken: "handler_access_token",
            refreshToken: "handler_refresh_token",
            expiresAt: Date().addingTimeInterval(3600)
        )
    ) {
        self.result = result
    }

    public var refreshTokenCalls: [String] {
        lock.lock()
        defer { lock.unlock() }
        return receivedTokens
    }

    public func refresh(using refreshToken: String) async throws -> SessionTokenRefresh {
        let (error, result) = recordAndSnapshot(refreshToken: refreshToken)
        if let error {
            throw error
        }
        return result
    }

    private func recordAndSnapshot(
        refreshToken: String
    ) -> (Error?, SessionTokenRefresh) {
        lock.lock()
        defer { lock.unlock() }
        receivedTokens.append(refreshToken)
        return (error, result)
    }
}
