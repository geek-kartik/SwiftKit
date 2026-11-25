import Foundation
import Security

/// Keychain Services-backed implementation of `KeychainClient`.
internal struct SystemKeychainClient: KeychainClient {
    internal init() {}

    internal func read(service: String, account: String) throws -> Data? {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData] = true
        query[kSecReturnAttributes] = true
        query[kSecMatchLimit] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw SecureStorageError.readFailed(status: status)
        }

        guard let item = result as? [CFString: Any],
              let data = item[kSecValueData] as? Data else {
            throw SecureStorageError.invalidData(key: account)
        }

        if let storedAccount = item[kSecAttrAccount] as? String, storedAccount != account {
            return nil
        }

        return data
    }

    internal func write(
        _ data: Data,
        service: String,
        account: String,
        accessibility: SecureStorageAccessibility
    ) throws {
        if let persistentRef = try exactMatchPersistentRef(service: service, account: account) {
            let query: [CFString: Any] = [kSecValuePersistentRef: persistentRef]
            let updates: [CFString: Any] = [
                kSecValueData: data,
                kSecAttrAccessible: accessibility.keychainValue
            ]
            let status = SecItemUpdate(query as CFDictionary, updates as CFDictionary)
            guard status == errSecSuccess else {
                throw SecureStorageError.updateFailed(status: status)
            }
            return
        }

        var attributes = baseQuery(service: service, account: account)
        attributes[kSecValueData] = data
        attributes[kSecAttrAccessible] = accessibility.keychainValue

        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem {
            if let persistentRef = try exactMatchPersistentRef(service: service, account: account, matchLimit: kSecMatchLimitAll) {
                let query: [CFString: Any] = [kSecValuePersistentRef: persistentRef]
                let updates: [CFString: Any] = [
                    kSecValueData: data,
                    kSecAttrAccessible: accessibility.keychainValue
                ]
                let updateStatus = SecItemUpdate(query as CFDictionary, updates as CFDictionary)
                guard updateStatus == errSecSuccess else {
                    throw SecureStorageError.updateFailed(status: updateStatus)
                }
                return
            }
            throw SecureStorageError.writeFailed(status: status)
        }

        guard status == errSecSuccess else {
            throw SecureStorageError.writeFailed(status: status)
        }
    }

    internal func delete(service: String, account: String) throws {
        guard let persistentRef = try exactMatchPersistentRef(service: service, account: account) else {
            return
        }

        let status = SecItemDelete([kSecValuePersistentRef: persistentRef] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecureStorageError.deleteFailed(status: status)
        }
    }

    internal func deleteAll(service: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecUseDataProtectionKeychain: true
        ]
        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecureStorageError.deleteFailed(status: status)
        }
    }

    private func exactMatchPersistentRef(service: String, account: String, matchLimit: CFString = kSecMatchLimitOne) throws -> Data? {
        var query = exactMatchQuery(service: service, account: account)
        query[kSecReturnAttributes] = true
        query[kSecReturnPersistentRef] = true
        query[kSecMatchLimit] = matchLimit

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw SecureStorageError.readFailed(status: status)
        }

        if let item = result as? [CFString: Any] {
            guard let storedAccount = item[kSecAttrAccount] as? String, storedAccount == account else {
                return nil
            }
            return item[kSecValuePersistentRef] as? Data
        }

        guard let items = result as? [[CFString: Any]] else {
            return nil
        }

        for item in items {
            if let storedAccount = item[kSecAttrAccount] as? String,
               storedAccount == account,
               let persistentRef = item[kSecValuePersistentRef] as? Data {
                return persistentRef
            }
        }

        return nil
    }

    private func exactMatchQuery(service: String, account: String) -> [CFString: Any] {
        baseQuery(service: service, account: account)
    }

    private func baseQuery(service: String, account: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecUseDataProtectionKeychain: true
        ]
    }
}
