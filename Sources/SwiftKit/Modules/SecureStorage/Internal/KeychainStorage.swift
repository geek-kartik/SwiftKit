import Foundation

/// Keychain-backed implementation of `SecureStorageProtocol`.
internal final class KeychainStorage: SecureStorageProtocol, Sendable {
    private let service: String
    private let accessibility: SecureStorageAccessibility
    private let client: KeychainClient
    private let logger: LoggerProtocol

    /// Creates a secure storage instance.
    /// - Parameters:
    ///   - service: Keychain service namespace. Defaults to the host bundle identifier.
    ///   - accessibility: Access policy applied to newly written items.
    ///   - client: Low-level Keychain adapter, injectable for tests.
    ///   - logger: Logger receiving failure diagnostics without sensitive values.
    internal init(
        service: String = Bundle.main.bundleIdentifier ?? "com.swiftkit.sdk",
        accessibility: SecureStorageAccessibility = .afterFirstUnlockThisDeviceOnly,
        client: KeychainClient = SystemKeychainClient(),
        logger: LoggerProtocol
    ) {
        self.service = service
        self.accessibility = accessibility
        self.client = client
        self.logger = logger
    }

    internal func setData(_ data: Data, forKey key: String) throws {
        try validate(key: key)
        do {
            try client.write(data, service: service, account: key, accessibility: accessibility)
        } catch {
            logFailure("write", error: error)
            throw error
        }
    }

    internal func data(forKey key: String) throws -> Data {
        try validate(key: key)

        let storedData: Data?
        do {
            storedData = try client.read(service: service, account: key)
        } catch {
            logFailure("read", error: error)
            throw error
        }

        guard let storedData else {
            throw SecureStorageError.itemNotFound(key: key)
        }
        return storedData
    }

    internal func contains(_ key: String) -> Bool {
        guard !key.isBlank else {
            return false
        }

        do {
            return try client.read(service: service, account: key) != nil
        } catch {
            logFailure("contains check", error: error)
            return false
        }
    }

    internal func remove(forKey key: String) throws {
        try validate(key: key)
        do {
            try client.delete(service: service, account: key)
        } catch {
            logFailure("delete", error: error)
            throw error
        }
    }

    internal func removeAll() throws {
        do {
            try client.deleteAll(service: service)
        } catch {
            logFailure("remove all", error: error)
            throw error
        }
    }

    private func validate(key: String) throws {
        guard !key.isBlank else {
            throw SecureStorageError.invalidKey
        }
    }

    private func logFailure(_ operation: String, error: Error) {
        let description = (error as? SecureStorageError)?.logDescription
            ?? String(describing: type(of: error))
        logger.error("Secure storage \(operation) failed: \(description)")
    }
}
