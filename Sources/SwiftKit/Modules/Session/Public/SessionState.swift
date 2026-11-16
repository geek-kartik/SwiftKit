import Foundation

/// Represents the current authentication state tracked by the session manager.
public enum SessionState: Equatable, Sendable {
    /// No authenticated session is currently active.
    case unauthenticated

    /// An authenticated, non-expired session is active.
    case authenticated(Session)

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
