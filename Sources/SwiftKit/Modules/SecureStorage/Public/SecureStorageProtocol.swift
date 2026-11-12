import Foundation

/// Public contract for securely persisting sensitive values in the system Keychain.
///
/// Values are scoped to the service configured by the concrete implementation.
/// String and `Codable` conveniences are provided through the protocol extension.
public protocol SecureStorageProtocol: Sendable {
    /// Persists a raw data value for the supplied key.
    /// - Parameters:
    ///   - data: The data to persist.
    ///   - key: A non-empty account key used to identify the value.
    /// - Throws: `SecureStorageError.invalidKey` when the key is blank, or a write failure.
    func setData(_ data: Data, forKey key: String) throws

    /// Retrieves raw data for the supplied key.
    /// - Parameter key: The account key to look up.
    /// - Returns: The stored data.
    /// - Throws: `SecureStorageError.itemNotFound` when no value exists, or a read failure.
    func data(forKey key: String) throws -> Data

    /// Persists a UTF-8 string value for the supplied key.
    /// - Parameters:
    ///   - value: The string to persist.
    ///   - key: A non-empty account key used to identify the value.
    /// - Throws: A storage failure.
    func setString(_ value: String, forKey key: String) throws

    /// Retrieves a UTF-8 string for the supplied key.
    /// - Parameter key: The account key to look up.
    /// - Returns: The stored string.
    /// - Throws: `SecureStorageError.itemNotFound` when no value exists, or a read failure.
    func string(forKey key: String) throws -> String

    /// Encodes and persists a `Codable` value using JSON.
    /// - Parameters:
    ///   - value: The value to encode and persist.
    ///   - key: A non-empty account key used to identify the value.
    /// - Throws: `SecureStorageError.encodingFailed` when encoding fails, or a storage failure.
    func setCodable<T: Encodable>(_ value: T, forKey key: String) throws

    /// Retrieves and decodes a JSON-encoded `Codable` value.
    /// - Parameters:
    ///   - type: The expected decoded type.
    ///   - key: The account key to look up.
    /// - Returns: The decoded value.
    /// - Throws: `SecureStorageError.decodingFailed` when decoding fails, or a read failure.
    func codable<T: Decodable>(_ type: T.Type, forKey key: String) throws -> T

    /// Indicates whether a value exists for the supplied key.
    /// - Parameter key: The account key to check.
    /// - Returns: `true` when a readable value exists; otherwise `false`.
    func contains(_ key: String) -> Bool

    /// Removes the value associated with the supplied key.
    /// Removing a key that does not exist succeeds without error.
    /// - Parameter key: The account key to remove.
    /// - Throws: A deletion failure.
    func remove(forKey key: String) throws

    /// Removes every value stored by this implementation's configured service.
    /// - Throws: A deletion failure.
    func removeAll() throws
}

public extension SecureStorageProtocol {
    /// Persists a UTF-8 string value for the supplied key.
    /// - Parameters:
    ///   - value: The string to persist.
    ///   - key: A non-empty account key used to identify the value.
    /// - Throws: A storage failure.
    func setString(_ value: String, forKey key: String) throws {
        try setData(Data(value.utf8), forKey: key)
    }

    /// Retrieves a UTF-8 string for the supplied key.
    /// - Parameter key: The account key to look up.
    /// - Returns: The stored string.
    /// - Throws: `SecureStorageError.itemNotFound` when no value exists, or a read failure.
    func string(forKey key: String) throws -> String {
        let storedData = try data(forKey: key)
        guard let value = String(data: storedData, encoding: .utf8) else {
            throw SecureStorageError.invalidData(key: key)
        }
        return value
    }

    /// Encodes and persists a `Codable` value using JSON.
    /// - Parameters:
    ///   - value: The value to encode and persist.
    ///   - key: A non-empty account key used to identify the value.
    /// - Throws: `SecureStorageError.encodingFailed` when encoding fails, or a storage failure.
    func setCodable<T: Encodable>(_ value: T, forKey key: String) throws {
        let encodedValue: Data
        do {
            encodedValue = try JSONEncoder().encode(value)
        } catch {
            throw SecureStorageError.encodingFailed
        }
        try setData(encodedValue, forKey: key)
    }

    /// Retrieves and decodes a JSON-encoded `Codable` value.
    /// - Parameters:
    ///   - type: The expected decoded type.
    ///   - key: The account key to look up.
    /// - Returns: The decoded value.
    /// - Throws: `SecureStorageError.decodingFailed` when decoding fails, or a read failure.
    func codable<T: Decodable>(_ type: T.Type, forKey key: String) throws -> T {
        let storedData = try data(forKey: key)
        do {
            return try JSONDecoder().decode(type, from: storedData)
        } catch {
            throw SecureStorageError.decodingFailed
        }
    }
}
