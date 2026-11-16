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
        }
    }
}
