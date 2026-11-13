import Foundation
@testable import SwiftKit

internal final class InMemoryKeychainClient: KeychainClient, @unchecked Sendable {
    private struct StorageKey: Hashable {
        let service: String
        let account: String
    }

    private let lock = NSLock()
    private var values: [StorageKey: Data] = [:]
    private var writeFailure: SecureStorageError?
    private var readFailure: SecureStorageError?
    private var deleteFailure: SecureStorageError?

    internal var failOnWrite: SecureStorageError? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return writeFailure
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            writeFailure = newValue
        }
    }

    internal var failOnRead: SecureStorageError? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return readFailure
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            readFailure = newValue
        }
    }

    internal var failOnDelete: SecureStorageError? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return deleteFailure
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            deleteFailure = newValue
        }
    }

    internal func read(service: String, account: String) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }

        if let readFailure {
            throw readFailure
        }

        return values[StorageKey(service: service, account: account)]
    }

    internal func write(
        _ data: Data,
        service: String,
        account: String,
        accessibility: SecureStorageAccessibility
    ) throws {
        lock.lock()
        defer { lock.unlock() }

        if let writeFailure {
            throw writeFailure
        }

        values[StorageKey(service: service, account: account)] = data
    }

    internal func delete(service: String, account: String) throws {
        lock.lock()
        defer { lock.unlock() }

        if let deleteFailure {
            throw deleteFailure
        }

        values.removeValue(forKey: StorageKey(service: service, account: account))
    }

    internal func deleteAll(service: String) throws {
        lock.lock()
        defer { lock.unlock() }

        if let deleteFailure {
            throw deleteFailure
        }

        values = values.filter { $0.key.service != service }
    }

    internal func count(forService service: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return values.keys.filter { $0.service == service }.count
    }
}
