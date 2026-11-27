import Foundation

/// Public contract for managing user session lifecycle and authentication state.
///
/// The manager persists the active session in secure storage, tracks expiration, and notifies
/// registered observers of authentication transitions. Implementations are responsible for
/// clearing credentials on logout, expiry, and unauthorized responses.
///
/// - Note: Observer callbacks are delivered synchronously on the thread that produced the
///   transition and are invoked outside the internal state lock, so observers may safely call back
///   into the manager.
public protocol SessionManagerProtocol: Sendable {
    /// The currently active session, or `nil` when unauthenticated or expired.
    ///
    /// This value reflects the in-memory session and does not perform storage cleanup. Call
    /// ``validateExpiry()`` to transition an expired session to ``SessionState/expired``.
    var currentSession: Session? { get }

    /// Whether an authenticated, non-expired session is currently active.
    var isAuthenticated: Bool { get }

    /// The current authentication state.
    ///
    /// Reports ``SessionState/expired`` when a stored session has expired but not yet been cleared.
    var state: SessionState { get }

    /// Establishes a new session, persisting it to secure storage.
    /// - Parameter session: The session to activate.
    /// - Throws: ``SessionError/invalidExpiry`` when the session expiration is not in the future,
    ///   or ``SessionError/storageFailure`` when persistence fails.
    func startSession(_ session: Session) throws

    /// Restores the persisted session from secure storage, if one exists.
    ///
    /// An already-expired stored session is cleared and reported through an
    /// ``SessionEvent/expired`` event rather than being returned.
    /// - Returns: The restored session, or `nil` when none is stored.
    /// - Throws: ``SessionError/decodingFailed`` when the stored value cannot be decoded, or
    ///   ``SessionError/storageFailure`` for other storage failures.
    func restoreSession() throws -> Session?

    /// Refreshes the active session with new credentials.
    ///
    /// The existing user identifier is preserved across the refresh. An expired session must be
    /// renewed through ``refreshSession()`` instead.
    /// - Parameters:
    ///   - accessToken: The new bearer access token.
    ///   - refreshToken: An optional new refresh token.
    ///   - expiresAt: The new absolute expiration date.
    /// - Throws: ``SessionError/noActiveSession`` when no session is stored,
    ///   ``SessionError/sessionExpired`` when the stored session has expired,
    ///   ``SessionError/invalidExpiry`` when the expiration is not in the future, or
    ///   ``SessionError/storageFailure`` when persistence fails.
    func refreshSession(accessToken: String, refreshToken: String?, expiresAt: Date) throws

    /// Renews the active or expired session using the configured ``SessionTokenRefreshHandler``.
    ///
    /// The stored refresh token is exchanged for new credentials, and the existing user identifier is
    /// preserved across the refresh. Refresh is skipped when the device is offline.
    /// - Returns: The refreshed session.
    /// - Throws: ``SessionError/noActiveSession`` when no session is stored,
    ///   ``SessionError/missingRefreshToken`` when the session has no refresh token,
    ///   ``SessionError/refreshHandlerUnavailable`` when no handler is configured,
    ///   ``SessionError/offline`` when the device is disconnected, ``SessionError/refreshCancelled``
    ///   when the refresh was cancelled, ``SessionError/refreshFailed`` when the handler fails, or
    ///   ``SessionError/storageFailure`` when persistence fails.
    func refreshSession() async throws -> Session

    /// Performs a secure logout, clearing the session from memory and secure storage.
    /// - Throws: ``SessionError/storageFailure`` when the stored session cannot be cleared.
    func logout() throws

    /// Transitions an expired session to ``SessionState/expired`` and emits a ``SessionEvent/expired`` event.
    ///
    /// The expired credentials are retained so the session may later be refreshed through
    /// ``refreshSession()``. Intended to be invoked on application lifecycle events such as returning to
    /// the foreground. Calling this method when no session is active or when the session is still valid
    /// has no effect.
    func validateExpiry()

    /// Clears the active session in response to an HTTP 401 unauthorized response.
    ///
    /// Emits an ``SessionEvent/unauthorized`` event. Intended to be invoked by the networking layer.
    func handleUnauthorized()

    /// Registers an observer for session transitions.
    ///
    /// The observer is notified of future transitions only. Read ``state`` for the current snapshot.
    /// - Parameter observer: Closure invoked for every subsequent session event.
    /// - Returns: A token that must be retained to remove the observer later.
    @discardableResult
    func addObserver(_ observer: @escaping @Sendable (SessionEvent) -> Void) -> SessionObservationToken

    /// Removes a previously registered observer.
    /// - Parameter token: The token returned when the observer was registered.
    func removeObserver(_ token: SessionObservationToken)
}
