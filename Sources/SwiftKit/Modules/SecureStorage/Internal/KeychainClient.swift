import Foundation

/// Internal abstraction over Keychain Services to keep storage logic testable off-device.
internal protocol KeychainClient: Sendable {
    /// Reads raw data for an account within a service.
    /// - Parameters:
    ///   - service: The Keychain service namespace.
    ///   - account: The account key to look up.
    /// - Returns: The stored data, or `nil` when no item exists.
    /// - Throws: `SecureStorageError` when the Keychain operation fails.
    func read(service: String, account: String) throws -> Data?

    /// Writes raw data for an account within a service, updating an existing item when present.
    /// - Parameters:
    ///   - data: The data to persist.
    ///   - service: The Keychain service namespace.
    ///   - account: The account key to write.
    ///   - accessibility: The access policy applied to the item.
    /// - Throws: `SecureStorageError` when the Keychain operation fails.
    func write(
        _ data: Data,
        service: String,
        account: String,
        accessibility: SecureStorageAccessibility
    ) throws

    /// Deletes a single account item. Missing items are ignored.
    /// - Parameters:
    ///   - service: The Keychain service namespace.
    ///   - account: The account key to delete.
    /// - Throws: `SecureStorageError` when the Keychain operation fails.
    func delete(service: String, account: String) throws

    /// Deletes every item belonging to a service. Missing items are ignored.
    /// - Parameter service: The Keychain service namespace.
    /// - Throws: `SecureStorageError` when the Keychain operation fails.
    func deleteAll(service: String) throws
}
