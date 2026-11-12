import Foundation

/// Keychain-backed implementation of `SecureStorageProtocol`.
internal final class KeychainStorage: SecureStorageProtocol, @unchecked Sendable {
    private let service: String
    private let accessibility: SecureStorageAccessibility
    private let client: KeychainClient

    /// Creates a secure storage instance.
    /// - Parameters:
    ///   - service: Keychain service namespace. Defaults to the host bundle identifier.
    ///   - accessibility: Access policy applied to newly written items.
    ///   - client: Low-level Keychain adapter, injectable for tests.
    internal init(
        service: String = Bundle.main.bundleIdentifier ?? "com.swiftkit.sdk",
        accessibility: SecureStorageAccessibility = .afterFirstUnlockThisDeviceOnly,
        client: KeychainClient = SystemKeychainClient()
    ) {
        self.service = service
        self.accessibility = accessibility
        self.client = client
    }

    internal func setData(_ data: Data, forKey key: String) throws {
        try validate(key: key)
        try client.write(data, service: service, account: key, accessibility: accessibility)
    }

    internal func data(forKey key: String) throws -> Data {
        try validate(key: key)
        guard let storedData = try client.read(service: service, account: key) else {
            throw SecureStorageError.itemNotFound(key: key)
        }
        return storedData
    }

    internal func contains(_ key: String) -> Bool {
        guard !key.isBlank else {
            return false
        }
        return (try? client.read(service: service, account: key)) != nil
    }

    internal func remove(forKey key: String) throws {
        try validate(key: key)
        try client.delete(service: service, account: key)
    }

    internal func removeAll() throws {
        try client.deleteAll(service: service)
    }

    private func validate(key: String) throws {
        guard !key.isBlank else {
            throw SecureStorageError.invalidKey
        }
    }
}
