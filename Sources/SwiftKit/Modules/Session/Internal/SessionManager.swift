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
    }

    private enum RestoreOutcome {
        case none
        case expired
        case restored(Session)
    }

    private let secureStorage: SecureStorageProtocol
    private let logger: LoggerProtocol
    private let now: @Sendable () -> Date
    private let storageKey: String
    private let stateBox: ThreadSafeBox<State>

    /// Creates a session manager.
    /// - Parameters:
    ///   - secureStorage: Secure storage used to persist the session.
    ///   - logger: Logger receiving lifecycle and transition diagnostics.
    ///   - storageKey: Secure storage key under which the session is persisted.
    ///   - now: Clock closure returning the current date, injectable for testing.
    internal init(
        secureStorage: SecureStorageProtocol,
        logger: LoggerProtocol,
        storageKey: String = "com.swiftkit.session.current",
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.secureStorage = secureStorage
        self.logger = logger
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
        if let session = activeSession() {
            return .authenticated(session)
        }
        return .unauthenticated
    }

    internal func startSession(_ session: Session) throws {
        try validateExpiry(of: session)
        try stateBox.mutate { state in
            try persist(session)
            state.session = session
        }
        logger.info("Session started.")
        notify(.authenticated(session))
    }

    internal func restoreSession() throws -> Session? {
        let outcome: RestoreOutcome = try stateBox.mutate { state in
            guard let stored = try readStoredSession() else {
                return .none
            }

            guard !stored.isExpired(at: now()) else {
                try? clearStoredSession()
                state.session = nil
                return .expired
            }

            state.session = stored
            return .restored(stored)
        }

        switch outcome {
        case .none:
            return nil
        case .expired:
            logger.info("The restored session had already expired and was cleared.")
            notify(.expired)
            return nil
        case .restored(let session):
            logger.info("Session restored.")
            notify(.authenticated(session))
            return session
        }
    }

    internal func refreshSession(accessToken: String, refreshToken: String?, expiresAt: Date) throws {
        let session: Session = try stateBox.mutate { state in
            guard let existingUserID = state.session?.userID else {
                throw SessionError.noActiveSession
            }

            let refreshed = Session(
                accessToken: accessToken,
                refreshToken: refreshToken,
                expiresAt: expiresAt,
                userID: existingUserID
            )

            guard refreshed.expiresAt > now() else {
                throw SessionError.invalidExpiry
            }

            try persist(refreshed)
            state.session = refreshed
            return refreshed
        }

        logger.info("Session refreshed.")
        notify(.refreshed(session))
    }

    internal func logout() throws {
        try stateBox.mutate { state in
            try clearStoredSession()
            state.session = nil
        }
        logger.info("Session logged out.")
        notify(.loggedOut)
    }

    internal func validateExpiry() {
        let expiredSession = stateBox.mutate { state -> Session? in
            guard let session = state.session, session.isExpired(at: now()) else {
                return nil
            }
            state.session = nil
            try? clearStoredSession()
            return session
        }

        guard expiredSession != nil else {
            return
        }

        logger.info("The active session expired and was cleared.")
        notify(.expired)
    }

    internal func handleUnauthorized() {
        stateBox.mutate { state in
            state.session = nil
            try? clearStoredSession()
        }
        logger.warning("Received an unauthorized response; the session was cleared.")
        notify(.unauthorized)
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

    private func notify(_ event: SessionEvent) {
        let observers = Array(stateBox.current.observers.values)
        for observer in observers {
            observer(event)
        }
    }
}
