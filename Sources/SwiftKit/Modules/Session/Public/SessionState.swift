import Foundation

/// Represents the current authentication state tracked by the session manager.
public enum SessionState: Equatable, Sendable {
    /// No authenticated session is currently active.
    case unauthenticated

    /// An authenticated, non-expired session is active.
    case authenticated(Session)

    /// A session was previously active but has since expired.
    ///
    /// The expired credentials are retained so the session can be refreshed through
    /// ``SessionManagerProtocol/refreshSession()``. Use ``session`` (which returns `nil`) or
    /// ``SessionManagerProtocol/currentSession`` to read the active session.
    case expired

    /// Indicates whether an authenticated session is currently active.
    public var isAuthenticated: Bool {
        if case .authenticated = self {
            return true
        }
        return false
    }

    /// The active session when authenticated; otherwise `nil`.
    public var session: Session? {
        if case .authenticated(let session) = self {
            return session
        }
        return nil
    }
}
