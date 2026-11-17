import Foundation

/// Errors produced during user session lifecycle management.
public enum SessionError: Error, LocalizedError, Equatable, Sendable {
    /// No active session exists for the requested operation.
    case noActiveSession

    /// The session has expired.
    case sessionExpired

    /// The supplied expiration date is not in the future.
    case invalidExpiry

    /// Persisting or clearing the session in secure storage failed.
    case storageFailure

    /// The stored session could not be decoded.
    case decodingFailed

    /// The active session has no refresh token available for renewal.
    case missingRefreshToken

    /// No ``SessionTokenRefreshHandler`` was configured to perform the refresh.
    case refreshHandlerUnavailable

    /// The token refresh handler failed to renew the session.
    case refreshFailed

    /// The device is offline and the session cannot be refreshed.
    case offline

    /// The in-flight token refresh was cancelled, typically due to a logout.
    case refreshCancelled

    /// A human-readable description of the session failure.
    public var errorDescription: String? {
        switch self {
        case .noActiveSession:
            return "No active session is available for the requested operation."
        case .sessionExpired:
            return "The session has expired and is no longer valid."
        case .invalidExpiry:
            return "The session expiration date must be in the future."
        case .storageFailure:
            return "Failed to persist or clear the session in secure storage."
        case .decodingFailed:
            return "Failed to decode the session retrieved from secure storage."
        case .missingRefreshToken:
            return "The active session does not contain a refresh token."
        case .refreshHandlerUnavailable:
            return "No token refresh handler has been configured for the session manager."
        case .refreshFailed:
            return "The token refresh handler failed to renew the session."
        case .offline:
            return "The device is offline and the session cannot be refreshed."
        case .refreshCancelled:
            return "The in-flight session refresh was cancelled."
        }
    }
}
