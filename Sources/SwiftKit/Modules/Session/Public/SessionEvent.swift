import Foundation

/// Represents a state transition emitted by the session manager.
///
/// Events describe transitions only. Use ``SessionManagerProtocol/state`` or
/// ``SessionManagerProtocol/currentSession`` to read the current snapshot.
public enum SessionEvent: Equatable, Sendable {
    /// A new session was established.
    case authenticated(Session)

    /// The active session was refreshed with new credentials.
    case refreshed(Session)

    /// The user was logged out and the session was cleared.
    case loggedOut

    /// The active session expired.
    case expired

    /// The backend rejected the session as unauthorized (HTTP 401).
    case unauthorized
}
