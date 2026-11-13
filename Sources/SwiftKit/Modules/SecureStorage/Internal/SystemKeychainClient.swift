import Foundation
import Security

/// Keychain Services-backed implementation of `KeychainClient`.
internal struct SystemKeychainClient: KeychainClient {
    internal init() {}

    internal func read(service: String, account: String) throws -> Data? {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw SecureStorageError.readFailed(status: status)
        }

        guard let data = result as? Data else {
            throw SecureStorageError.invalidData(key: account)
        }

        return data
    }

    internal func write(
        _ data: Data,
        service: String,
        account: String,
        accessibility: SecureStorageAccessibility
    ) throws {
        var attributes = baseQuery(service: service, account: account)
        attributes[kSecValueData] = data
        attributes[kSecAttrAccessible] = accessibility.keychainValue

        var status = SecItemAdd(attributes as CFDictionary, nil)

        if status == errSecDuplicateItem {
            let query = baseQuery(service: service, account: account)
            let updates: [CFString: Any] = [
                kSecValueData: data,
                kSecAttrAccessible: accessibility.keychainValue
            ]
            status = SecItemUpdate(query as CFDictionary, updates as CFDictionary)

            guard status == errSecSuccess else {
                throw SecureStorageError.updateFailed(status: status)
            }
            return
        }

        guard status == errSecSuccess else {
            throw SecureStorageError.writeFailed(status: status)
        }
    }

    internal func delete(service: String, account: String) throws {
        let status = SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)

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

    private func baseQuery(service: String, account: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecUseDataProtectionKeychain: true
        ]
    }
}
