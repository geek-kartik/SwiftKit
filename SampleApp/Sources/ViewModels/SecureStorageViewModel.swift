import Foundation
import SwiftUI
import SwiftKit

public enum SecureStorageFeedbackStyle: Equatable, Sendable {
    case success
    case info
    case warning
    case error
}

public struct SecureStorageFeedback: Equatable, Sendable {
    public let message: String
    public let style: SecureStorageFeedbackStyle

    public init(message: String, style: SecureStorageFeedbackStyle) {
        self.message = message
        self.style = style
    }
}

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
    @Published public var profileKey: String = "session_profile_key"
    @Published public var retrievedProfile: SampleSessionProfile?
    @Published public var savedProfile: SampleSessionProfile?
    @Published public var isProfileStored: Bool = false
    @Published public var profileFeedback: SecureStorageFeedback?

    public var hasUnsavedProfileChanges: Bool {
        guard let savedProfile else { return false }
        return profileUserId != savedProfile.userId
            || profileUsername != savedProfile.username
            || profileRole != savedProfile.role
    }

    private let secureStorage: SecureStorageProtocol
    private let logger: LoggerProtocol

    public init(
        secureStorage: SecureStorageProtocol? = nil,
        logger: LoggerProtocol? = nil
    ) {
        self.secureStorage = secureStorage ?? SDKService.shared.secureStorage
        self.logger = logger ?? SDKService.shared.logger
        self.isProfileStored = self.secureStorage.contains(self.profileKey)
        self.profileFeedback = self.isProfileStored
            ? SecureStorageFeedback(
                message: "A saved profile exists. Tap Read Profile to load it.",
                style: .info
            )
            : SecureStorageFeedback(
                message: "No saved profile yet. Fill in the fields and tap Save Profile first.",
                style: .info
            )
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
            logger.info("SecureStorage: retrieved string for key: \(inputKey)")
            setStatus("Successfully retrieved string for key '\(inputKey)'.", isError: false)
        } catch let error as SecureStorageError {
            retrievedValue = ""
            logger.warning("SecureStorage read warning: \(error.localizedDescription)")
            setStatus("Storage Error: \(error.localizedDescription)", isError: true)
        } catch {
            retrievedValue = ""
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
    public func saveProfile(key: String? = nil) {
        let targetKey = resolvedProfileKey(key)

        guard !targetKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            setProfileFeedback("Profile key cannot be empty.", style: .warning)
            setStatus("Profile key cannot be empty.", isError: true)
            return
        }
        guard !profileUserId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !profileUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            setProfileFeedback("User ID and Username are required.", style: .warning)
            setStatus("User ID and Username are required.", isError: true)
            return
        }

        let profile = SampleSessionProfile(
            userId: profileUserId,
            username: profileUsername,
            role: profileRole,
            issuedAt: Date()
        )

        do {
            try secureStorage.setCodable(profile, forKey: targetKey)
            savedProfile = profile
            retrievedProfile = profile
            isProfileStored = true
            setProfileFeedback("Saved. You can now read the profile back.", style: .success)
            logger.info("SecureStorage: saved Codable profile for key: \(targetKey)")
            setStatus("Saved Codable profile successfully.", isError: false)
        } catch let error as SecureStorageError {
            setProfileFeedback("Could not save the profile: \(error.localizedDescription)", style: .error)
            logger.error("SecureStorage profile save error: \(error.localizedDescription)")
            setStatus("Storage Error: \(error.localizedDescription)", isError: true)
        } catch {
            setProfileFeedback("Could not save the profile: \(error.localizedDescription)", style: .error)
            logger.error("SecureStorage profile unexpected save error: \(error.localizedDescription)")
            setStatus("Unexpected Error: \(error.localizedDescription)", isError: true)
        }
    }

    /// Demonstrates retrieving a Codable struct using `codable(_:forKey:)`.
    public func readProfile(key: String? = nil) {
        let targetKey = resolvedProfileKey(key)

        guard !targetKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            setProfileFeedback("Profile key cannot be empty.", style: .warning)
            setStatus("Profile key cannot be empty.", isError: true)
            return
        }

        guard secureStorage.contains(targetKey) else {
            retrievedProfile = nil
            savedProfile = nil
            isProfileStored = false
            setProfileFeedback("No saved profile yet. Fill in the fields and tap Save Profile first.", style: .info)
            setStatus("No saved profile yet. Save it before reading.", isError: false)
            return
        }

        do {
            let profile = try secureStorage.codable(SampleSessionProfile.self, forKey: targetKey)
            retrievedProfile = profile
            savedProfile = profile
            isProfileStored = true
            setProfileFeedback("Loaded saved profile for \(profile.username).", style: .success)
            logger.info("SecureStorage: retrieved Codable profile for key: \(targetKey)")
            setStatus("Retrieved Codable profile for user: \(profile.username)", isError: false)
        } catch let error as SecureStorageError {
            retrievedProfile = nil
            if case .itemNotFound = error {
                savedProfile = nil
                isProfileStored = false
                setProfileFeedback("No saved profile yet. Fill in the fields and tap Save Profile first.", style: .info)
                setStatus("No saved profile yet. Save it before reading.", isError: false)
            } else {
                isProfileStored = true
                let message = profileReadFailureMessage(for: error)
                setProfileFeedback(message, style: .error)
                logger.warning("SecureStorage profile read warning: \(error.localizedDescription)")
                setStatus("Storage Error: \(error.localizedDescription)", isError: true)
            }
        } catch {
            retrievedProfile = nil
            setProfileFeedback("Could not read the profile: \(error.localizedDescription)", style: .error)
            logger.error("SecureStorage profile unexpected read error: \(error.localizedDescription)")
            setStatus("Unexpected Error: \(error.localizedDescription)", isError: true)
        }
    }

    /// Updates the inline feedback after any profile field changes.
    public func profileFieldsChanged() {
        if !isProfileStored {
            setProfileFeedback("Not saved yet. Tap Save Profile to persist this profile.", style: .info)
        } else if savedProfile == nil {
            setProfileFeedback("A saved profile exists. Tap Read Profile to load it.", style: .info)
        } else if hasUnsavedProfileChanges {
            setProfileFeedback("Unsaved changes. Tap Save Changes to persist them.", style: .warning)
        } else {
            setProfileFeedback("Matches the saved profile.", style: .success)
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
            savedProfile = nil
            isProfileStored = false
            containsKeyResult = false
            setProfileFeedback("All secure storage items were cleared, including the saved profile.", style: .info)
            logger.warning("SecureStorage: cleared all Keychain items for configured service.")
            setStatus("All secure storage items cleared successfully.", isError: false)
        } catch {
            logger.error("SecureStorage clearAll error: \(error.localizedDescription)")
            setStatus("Clear All Error: \(error.localizedDescription)", isError: true)
        }
    }

    private func resolvedProfileKey(_ key: String?) -> String {
        if let key {
            profileKey = key
        }
        return profileKey
    }

    private func setProfileFeedback(_ message: String, style: SecureStorageFeedbackStyle) {
        profileFeedback = SecureStorageFeedback(message: message, style: style)
    }

    private func profileReadFailureMessage(for error: SecureStorageError) -> String {
        switch error {
        case .decodingFailed, .invalidData:
            return "The saved profile could not be decoded. Tap Save Profile to replace it."
        case .readFailed:
            return "The saved profile could not be read. Try again."
        default:
            return "Could not read the profile: \(error.localizedDescription)"
        }
    }

    private func setStatus(_ message: String, isError: Bool) {
        statusMessage = message
        isErrorMessage = isError
    }
}
