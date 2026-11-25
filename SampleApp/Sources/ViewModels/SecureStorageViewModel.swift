import Foundation
import SwiftUI
import SwiftKit

/// ViewModel managing user interactions and demonstrations for `SecureStorageProtocol`.
@MainActor
public final class SecureStorageViewModel: ObservableObject {
    @Published public var inputKey: String = "sample_api_token"
    @Published public var inputValue: String = "sample_secret_token_abc123"
    @Published public var retrievedValue: String = ""
    @Published public var containsKeyResult: Bool?
    @Published public var statusMessage: String = ""
    @Published public var isErrorMessage: Bool = false

    // Codable profile demonstration fields
    @Published public var profileUserId: String = "user_42"
    @Published public var profileUsername: String = "johndoe"
    @Published public var profileRole: String = "Administrator"
    @Published public var retrievedProfile: SampleSessionProfile?

    private let secureStorage: SecureStorageProtocol
    private let logger: LoggerProtocol

    public init(
        secureStorage: SecureStorageProtocol? = nil,
        logger: LoggerProtocol? = nil
    ) {
        self.secureStorage = secureStorage ?? SDKService.shared.secureStorage
        self.logger = logger ?? SDKService.shared.logger
    }

    // MARK: - String Operations

    /// Persists string in Keychain using `setString(_:forKey:)`.
    public func saveString() {
        guard !inputKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            setStatus("Key cannot be empty.", isError: true)
            return
        }

        do {
            try secureStorage.setString(inputValue, forKey: inputKey)
            logger.info("SecureStorage: saved string for key: \(inputKey)")
            setStatus("Successfully saved string value for key '\(inputKey)'.", isError: false)
            checkContains()
        } catch let error as SecureStorageError {
            logger.error("SecureStorage write error: \(error.localizedDescription)")
            setStatus("Storage Error: \(error.localizedDescription)", isError: true)
        } catch {
            logger.error("SecureStorage unexpected write error: \(error.localizedDescription)")
            setStatus("Unexpected Error: \(error.localizedDescription)", isError: true)
        }
    }

    /// Reads string from Keychain using `string(forKey:)`.
    public func readString() {
        guard !inputKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            setStatus("Key cannot be empty.", isError: true)
            return
        }

        do {
            let val = try secureStorage.string(forKey: inputKey)
            retrievedValue = val
            containsKeyResult = true
            logger.info("SecureStorage: retrieved string for key: \(inputKey)")
            setStatus("Successfully retrieved string for key '\(inputKey)'.", isError: false)
        } catch let error as SecureStorageError {
            retrievedValue = ""
            containsKeyResult = secureStorage.contains(inputKey)
            logger.warning("SecureStorage read warning: \(error.localizedDescription)")
            setStatus("Storage Error: \(error.localizedDescription)", isError: true)
        } catch {
            retrievedValue = ""
            containsKeyResult = secureStorage.contains(inputKey)
            logger.error("SecureStorage unexpected read error: \(error.localizedDescription)")
            setStatus("Unexpected Error: \(error.localizedDescription)", isError: true)
        }
    }

    /// Updates existing string in Keychain (in SwiftKit `setString` handles upsert).
    public func updateString() {
        saveString()
    }

    /// Deletes value for key from Keychain using `remove(forKey:)`.
    public func removeKey() {
        guard !inputKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            setStatus("Key cannot be empty.", isError: true)
            return
        }

        do {
            try secureStorage.remove(forKey: inputKey)
            retrievedValue = ""
            logger.info("SecureStorage: removed key: \(inputKey)")
            setStatus("Successfully removed key '\(inputKey)'.", isError: false)
            checkContains()
        } catch let error as SecureStorageError {
            logger.error("SecureStorage remove error: \(error.localizedDescription)")
            setStatus("Storage Error: \(error.localizedDescription)", isError: true)
        } catch {
            logger.error("SecureStorage unexpected remove error: \(error.localizedDescription)")
            setStatus("Unexpected Error: \(error.localizedDescription)", isError: true)
        }
    }

    /// Verifies if a key exists in Keychain using `contains(_:)`.
    public func checkContains() {
        guard !inputKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            containsKeyResult = nil
            return
        }
        let exists = secureStorage.contains(inputKey)
        containsKeyResult = exists
        logger.debug("SecureStorage: checked contains for key '\(inputKey)' -> \(exists)")
    }

    // MARK: - Codable Operations

    /// Demonstrates storing a Codable struct using `setCodable(_:forKey:)`.
    public func saveProfile(key: String = "session_profile_key") {
        let profile = SampleSessionProfile(
            userId: profileUserId,
            username: profileUsername,
            role: profileRole,
            issuedAt: Date()
        )

        do {
            try secureStorage.setCodable(profile, forKey: key)
            logger.info("SecureStorage: saved Codable profile for key: \(key)")
            setStatus("Saved Codable profile successfully.", isError: false)
        } catch let error as SecureStorageError {
            logger.error("SecureStorage profile save error: \(error.localizedDescription)")
            setStatus("Storage Error: \(error.localizedDescription)", isError: true)
        } catch {
            logger.error("SecureStorage profile unexpected save error: \(error.localizedDescription)")
            setStatus("Unexpected Error: \(error.localizedDescription)", isError: true)
        }
    }

    /// Demonstrates retrieving a Codable struct using `codable(_:forKey:)`.
    public func readProfile(key: String = "session_profile_key") {
        retrievedProfile = nil
        do {
            let profile = try secureStorage.codable(SampleSessionProfile.self, forKey: key)
            guard profile.userId == profileUserId else {
                logger.warning("SecureStorage: decoded profile user ID does not match '\(profileUserId)'")
                setStatus("No profile found for user ID '\(profileUserId)'.", isError: true)
                return
            }
            retrievedProfile = profile
            logger.info("SecureStorage: retrieved Codable profile for key: \(key)")
            setStatus("Retrieved Codable profile for user: \(profile.username)", isError: false)
        } catch let error as SecureStorageError {
            logger.warning("SecureStorage profile read warning: \(error.localizedDescription)")
            setStatus("Storage Error: \(error.localizedDescription)", isError: true)
        } catch {
            logger.error("SecureStorage profile unexpected read error: \(error.localizedDescription)")
            setStatus("Unexpected Error: \(error.localizedDescription)", isError: true)
        }
    }

    // MARK: - Data Operations

    /// Demonstrates raw Data storage using `setData(_:forKey:)` and `data(forKey:)`.
    public func testDataPersistence(key: String = "raw_data_sample_key") {
        let sampleBytes: [UInt8] = [0x53, 0x77, 0x69, 0x66, 0x74, 0x4B, 0x69, 0x74] // "SwiftKit"
        let data = Data(sampleBytes)

        do {
            try secureStorage.setData(data, forKey: key)
            let retrieved = try secureStorage.data(forKey: key)
            let match = (retrieved == data)
            logger.info("SecureStorage: raw Data round-trip success: \(match)")
            setStatus("Raw Data saved and retrieved successfully (\(retrieved.count) bytes).", isError: false)
        } catch {
            logger.error("SecureStorage: raw Data test failed: \(error.localizedDescription)")
            setStatus("Data Error: \(error.localizedDescription)", isError: true)
        }
    }

    // MARK: - Remove All

    /// Removes every key stored in the service namespace using `removeAll()`.
    public func clearAllStorage() {
        do {
            try secureStorage.removeAll()
            retrievedValue = ""
            retrievedProfile = nil
            containsKeyResult = false
            logger.warning("SecureStorage: cleared all Keychain items for configured service.")
            setStatus("All secure storage items cleared successfully.", isError: false)
        } catch {
            logger.error("SecureStorage clearAll error: \(error.localizedDescription)")
            setStatus("Clear All Error: \(error.localizedDescription)", isError: true)
        }
    }

    private func setStatus(_ message: String, isError: Bool) {
        statusMessage = message
        isErrorMessage = isError
    }
}
