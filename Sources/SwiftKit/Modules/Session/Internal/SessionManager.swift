import Foundation

/// Concrete session manager persisting credentials in secure storage.
///
/// - Note: This type relies on compiler-checked `Sendable` conformance. All stored properties are
///   immutable and `Sendable`; mutable session and observer state is confined to ``ThreadSafeBox``,
///   whose locking makes the shared state safe across concurrency domains. Each lifecycle operation
///   mutates in-memory state and secure storage atomically under the box lock, while observer
///   callbacks are invoked outside the lock.
internal final class SessionManager: SessionManagerProtocol {
    private struct State: Sendable {
        var session: Session?
        var observers: [SessionObservationToken: @Sendable (SessionEvent) -> Void] = [:]
        var lastNotifiedState: SessionState?
        var refreshTask: Task<Session, Error>?
        var refreshID: UUID?
    }

    private enum RestoreOutcome {
        case none
        case expired
        case restored(Session)
    }

    private let secureStorage: SecureStorageProtocol
    private let logger: LoggerProtocol
    private let connectivity: ConnectivityMonitorProtocol?
    private let refreshHandler: SessionTokenRefreshHandler?
    private let now: @Sendable () -> Date
    private let storageKey: String
    private let stateBox: ThreadSafeBox<State>

    /// Creates a session manager.
    /// - Parameters:
    ///   - secureStorage: Secure storage used to persist the session.
    ///   - logger: Logger receiving lifecycle and transition diagnostics.
    ///   - connectivity: Optional connectivity monitor used to skip refresh while offline.
    ///   - refreshHandler: Optional handler performing the backend token exchange.
    ///   - storageKey: Secure storage key under which the session is persisted.
    ///   - now: Clock closure returning the current date, injectable for testing.
    internal init(
        secureStorage: SecureStorageProtocol,
        logger: LoggerProtocol,
        connectivity: ConnectivityMonitorProtocol? = nil,
        refreshHandler: SessionTokenRefreshHandler? = nil,
        storageKey: String = "com.swiftkit.session.current",
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.secureStorage = secureStorage
        self.logger = logger
        self.connectivity = connectivity
        self.refreshHandler = refreshHandler
        self.storageKey = storageKey
        self.now = now
        self.stateBox = ThreadSafeBox(State())
    }

    internal var currentSession: Session? {
        activeSession()
    }

    internal var isAuthenticated: Bool {
        activeSession() != nil
    }

    internal var state: SessionState {
        guard let session = stateBox.current.session else {
            return .unauthenticated
        }
        return session.isExpired(at: now()) ? .expired : .authenticated(session)
    }

    internal func startSession(_ session: Session) throws {
        try validateExpiry(of: session)
        try stateBox.mutate { state in
            cancelInFlightRefresh(&state)
            try persist(session)
            state.session = session
        }
        logger.info("Session started.")
        notify(.authenticated(session), state: .authenticated(session))
    }

    internal func restoreSession() throws -> Session? {
        let outcome: RestoreOutcome = try stateBox.mutate { state in
            guard let stored = try readStoredSession() else {
                return .none
            }

            cancelInFlightRefresh(&state)

            guard !stored.isExpired(at: now()) else {
                state.session = stored
                return .expired
            }

            state.session = stored
            return .restored(stored)
        }

        switch outcome {
        case .none:
            return nil
        case .expired:
            logger.info("The restored session had already expired.")
            notify(.expired, state: .expired)
            return nil
        case .restored(let session):
            logger.info("Session restored.")
            notify(.authenticated(session), state: .authenticated(session))
            return session
        }
    }

    internal func refreshSession(accessToken: String, refreshToken: String?, expiresAt: Date) throws {
        let session: Session = try stateBox.mutate { state in
            guard let existing = state.session else {
                throw SessionError.noActiveSession
            }
            guard !existing.isExpired(at: now()) else {
                throw SessionError.sessionExpired
            }

            let refreshed = Session(
                accessToken: accessToken,
                refreshToken: refreshToken,
                expiresAt: expiresAt,
                userID: existing.userID
            )

            guard refreshed.expiresAt > now() else {
                throw SessionError.invalidExpiry
            }

            cancelInFlightRefresh(&state)
            try persist(refreshed)
            state.session = refreshed
            return refreshed
        }

        logger.info("Session refreshed.")
        notify(.refreshed(session), state: .authenticated(session))
    }

    internal func refreshSession() async throws -> Session {
        let request: (task: Task<Session, Error>, id: UUID) = try stateBox.mutate { state in
            guard let session = state.session else {
                throw SessionError.noActiveSession
            }

            guard let refreshToken = session.refreshToken else {
                throw SessionError.missingRefreshToken
            }

            guard let handler = refreshHandler else {
                throw SessionError.refreshHandlerUnavailable
            }

            guard connectivity?.currentStatus != .disconnected else {
                throw SessionError.offline
            }

            state.refreshTask?.cancel()

            let id = UUID()
            let now = self.now
            let task = Task<Session, Error> {
                let result = try await handler.refresh(using: refreshToken)
                let refreshed = Session(
                    accessToken: result.accessToken,
                    refreshToken: result.refreshToken ?? refreshToken,
                    expiresAt: result.expiresAt,
                    userID: session.userID
                )
                guard refreshed.expiresAt > now() else {
                    throw SessionError.invalidExpiry
                }
                return refreshed
            }
            state.refreshTask = task
            state.refreshID = id
            return (task, id)
        }

        let refreshed: Session
        do {
            refreshed = try await request.task.value
        } catch is CancellationError {
            clearInFlightRefresh(id: request.id)
            throw SessionError.refreshCancelled
        } catch let error as SessionError {
            clearInFlightRefresh(id: request.id)
            throw error
        } catch {
            clearInFlightRefresh(id: request.id)
            throw SessionError.refreshFailed
        }

        let committed: Session = try stateBox.mutate { state in
            guard state.refreshID == request.id else {
                throw SessionError.refreshCancelled
            }
            state.refreshTask = nil
            state.refreshID = nil
            try persist(refreshed)
            state.session = refreshed
            return refreshed
        }

        logger.info("Session refreshed.")
        notify(.refreshed(committed), state: .authenticated(committed))
        return committed
    }

    internal func logout() throws {
        try stateBox.mutate { state in
            cancelInFlightRefresh(&state)
            try clearStoredSession()
            state.session = nil
        }
        logger.info("Session logged out.")
        notify(.loggedOut, state: .unauthenticated)
    }

    internal func validateExpiry() {
        let didExpire = stateBox.mutate { state -> Bool in
            guard let session = state.session, session.isExpired(at: now()) else {
                return false
            }
            return true
        }

        guard didExpire else {
            return
        }

        logger.info("The active session expired.")
        notify(.expired, state: .expired)
    }

    internal func handleUnauthorized() {
        stateBox.mutate { state in
            cancelInFlightRefresh(&state)
            state.session = nil
            try? clearStoredSession()
        }
        logger.warning("Received an unauthorized response; the session was cleared.")
        notify(.unauthorized, state: .unauthenticated)
    }

    @discardableResult
    internal func addObserver(
        _ observer: @escaping @Sendable (SessionEvent) -> Void
    ) -> SessionObservationToken {
        let token = SessionObservationToken()
        stateBox.mutate { $0.observers[token] = observer }
        return token
    }

    internal func removeObserver(_ token: SessionObservationToken) {
        stateBox.mutate { $0.observers.removeValue(forKey: token) }
    }

    // MARK: - Private

    private func activeSession() -> Session? {
        guard let session = stateBox.current.session else {
            return nil
        }
        return session.isExpired(at: now()) ? nil : session
    }

    private func validateExpiry(of session: Session) throws {
        guard session.expiresAt > now() else {
            throw SessionError.invalidExpiry
        }
    }

    private func cancelInFlightRefresh(_ state: inout State) {
        state.refreshTask?.cancel()
        state.refreshTask = nil
        state.refreshID = nil
    }

    private func clearInFlightRefresh(id: UUID) {
        stateBox.mutate { state in
            guard state.refreshID == id else { return }
            state.refreshTask = nil
            state.refreshID = nil
        }
    }

    private func readStoredSession() throws -> Session? {
        do {
            return try secureStorage.codable(Session.self, forKey: storageKey)
        } catch let error as SecureStorageError {
            switch error {
            case .itemNotFound:
                return nil
            case .decodingFailed:
                logger.error("Failed to decode the stored session.")
                throw SessionError.decodingFailed
            default:
                logger.error("Failed to read the stored session.")
                throw SessionError.storageFailure
            }
        } catch {
            logger.error("Failed to read the stored session.")
            throw SessionError.storageFailure
        }
    }

    private func persist(_ session: Session) throws {
        do {
            try secureStorage.setCodable(session, forKey: storageKey)
        } catch {
            logger.error("Failed to persist the session to secure storage.")
            throw SessionError.storageFailure
        }
    }

    private func clearStoredSession() throws {
        do {
            try secureStorage.remove(forKey: storageKey)
        } catch {
            logger.error("Failed to clear the stored session from secure storage.")
            throw SessionError.storageFailure
        }
    }

    private func notify(_ event: SessionEvent, state newState: SessionState) {
        let shouldDeliver = stateBox.mutate { state -> Bool in
            guard state.lastNotifiedState != newState else {
                return false
            }
            state.lastNotifiedState = newState
            return true
        }

        guard shouldDeliver else {
            return
        }

        let observers = Array(stateBox.current.observers.values)
        for observer in observers {
            observer(event)
        }
    }
}
