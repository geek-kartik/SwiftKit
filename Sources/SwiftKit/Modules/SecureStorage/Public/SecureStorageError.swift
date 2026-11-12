import Foundation
import Security

/// Errors produced by secure Keychain-backed storage operations.
public enum SecureStorageError: Error, LocalizedError, Equatable, Sendable {
    /// The supplied account key was empty or contained only whitespace.
    case invalidKey
    /// No value was found for the supplied key.
    case itemNotFound(key: String)
    /// Writing a new value failed with the supplied Keychain status.
    case writeFailed(status: OSStatus)
    /// Updating an existing value failed with the supplied Keychain status.
    case updateFailed(status: OSStatus)
    /// Reading a value failed with the supplied Keychain status.
    case readFailed(status: OSStatus)
    /// Deleting a value failed with the supplied Keychain status.
    case deleteFailed(status: OSStatus)
    /// A value could not be encoded before storage.
    case encodingFailed
    /// A stored value could not be decoded.
    case decodingFailed
    /// A stored value was not valid for the requested representation.
    case invalidData(key: String)

    /// A human-readable description of the storage failure.
    public var errorDescription: String? {
        switch self {
        case .invalidKey:
            return "Secure storage keys must not be empty."
        case .itemNotFound(let key):
            return "No secure storage item was found for key: \(key)"
        case .writeFailed(let status):
            return "Failed to write secure storage item with OSStatus: \(status)"
        case .updateFailed(let status):
            return "Failed to update secure storage item with OSStatus: \(status)"
        case .readFailed(let status):
            return "Failed to read secure storage item with OSStatus: \(status)"
        case .deleteFailed(let status):
            return "Failed to delete secure storage item with OSStatus: \(status)"
        case .encodingFailed:
            return "Failed to encode the value before secure storage."
        case .decodingFailed:
            return "Failed to decode the value retrieved from secure storage."
        case .invalidData(let key):
            return "The value stored for key '\(key)' is not valid for the requested representation."
        }
    }
}
