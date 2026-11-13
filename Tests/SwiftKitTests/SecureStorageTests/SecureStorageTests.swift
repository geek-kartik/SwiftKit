import Security
import XCTest
@testable import SwiftKit

private struct TestProfile: Codable, Equatable {
    let identifier: String
    let displayName: String
}

final class SecureStorageTests: XCTestCase {
    private var client: InMemoryKeychainClient!
    private var logger: MockLogger!
    private var storage: KeychainStorage!

    override func setUp() {
        super.setUp()
        client = InMemoryKeychainClient()
        logger = MockLogger()
        storage = KeychainStorage(
            service: "com.swiftkit.tests.secure-storage",
            client: client,
            logger: logger
        )
    }

    override func tearDown() {
        storage = nil
        logger = nil
        client = nil
        super.tearDown()
    }

    func testSetAndGetString() throws {
        try storage.setString("secret-value", forKey: "token")

        XCTAssertEqual(try storage.string(forKey: "token"), "secret-value")
        XCTAssertTrue(storage.contains("token"))
    }

    func testSetAndGetData() throws {
        let payload = Data([0x01, 0x02, 0x03, 0x04])

        try storage.setData(payload, forKey: "payload")

        XCTAssertEqual(try storage.data(forKey: "payload"), payload)
        XCTAssertTrue(storage.contains("payload"))
    }

    func testOverwriteExistingValue() throws {
        try storage.setString("first-value", forKey: "token")
        try storage.setString("second-value", forKey: "token")

        XCTAssertEqual(try storage.string(forKey: "token"), "second-value")
        XCTAssertEqual(client.count(forService: "com.swiftkit.tests.secure-storage"), 1)
    }

    func testMissingKeyThrowsItemNotFound() {
        XCTAssertThrowsError(try storage.string(forKey: "missing")) { error in
            XCTAssertEqual(error as? SecureStorageError, .itemNotFound(key: "missing"))
        }
    }

    func testCodableRoundTrip() throws {
        let profile = TestProfile(identifier: "usr_1", displayName: "Archana")

        try storage.setCodable(profile, forKey: "profile")

        XCTAssertEqual(try storage.codable(TestProfile.self, forKey: "profile"), profile)
    }

    func testDecodingInvalidDataThrows() throws {
        try storage.setData(Data("not-json".utf8), forKey: "profile")

        XCTAssertThrowsError(try storage.codable(TestProfile.self, forKey: "profile")) { error in
            XCTAssertEqual(error as? SecureStorageError, .decodingFailed)
        }
    }

    func testRemoveDeletesValue() throws {
        try storage.setString("value", forKey: "token")

        try storage.remove(forKey: "token")

        XCTAssertFalse(storage.contains("token"))
    }

    func testRemoveIsIdempotent() throws {
        try storage.setString("value", forKey: "token")

        try storage.remove(forKey: "token")

        XCTAssertNoThrow(try storage.remove(forKey: "token"))
    }

    func testRemoveAllOnlyDeletesMatchingService() throws {
        let otherStorage = KeychainStorage(
            service: "com.swiftkit.tests.other",
            client: client,
            logger: logger
        )

        try storage.setString("first", forKey: "one")
        try otherStorage.setString("second", forKey: "two")

        try storage.removeAll()

        XCTAssertFalse(storage.contains("one"))
        XCTAssertEqual(try otherStorage.string(forKey: "two"), "second")
        XCTAssertEqual(client.count(forService: "com.swiftkit.tests.secure-storage"), 0)
        XCTAssertEqual(client.count(forService: "com.swiftkit.tests.other"), 1)
    }

    func testBlankKeyThrowsInvalidKey() {
        XCTAssertThrowsError(try storage.setString("value", forKey: "")) { error in
            XCTAssertEqual(error as? SecureStorageError, .invalidKey)
        }

        XCTAssertThrowsError(try storage.data(forKey: "   ")) { error in
            XCTAssertEqual(error as? SecureStorageError, .invalidKey)
        }

        XCTAssertFalse(storage.contains(""))
    }

    func testReadFailurePropagates() {
        client.failOnRead = .readFailed(status: -1)

        XCTAssertThrowsError(try storage.data(forKey: "token")) { error in
            XCTAssertEqual(error as? SecureStorageError, .readFailed(status: -1))
        }
        XCTAssertFalse(storage.contains("token"))
    }

    func testWriteFailurePropagates() {
        client.failOnWrite = .writeFailed(status: -2)

        XCTAssertThrowsError(try storage.setString("value", forKey: "token")) { error in
            XCTAssertEqual(error as? SecureStorageError, .writeFailed(status: -2))
        }
    }

    func testWriteFailureIsLoggedWithoutKey() {
        client.failOnWrite = .writeFailed(status: -2)

        XCTAssertThrowsError(try storage.setString("value", forKey: "sensitive-account-key"))

        XCTAssertTrue(logger.recordedLevels.contains(.error))
        XCTAssertTrue(logger.recordedEntries.contains { $0.message.contains("writeFailed") })
        XCTAssertFalse(logger.recordedEntries.contains { $0.message.contains("sensitive-account-key") })
    }

    func testReadFailureIsLogged() {
        client.failOnRead = .readFailed(status: -1)

        XCTAssertThrowsError(try storage.data(forKey: "token"))

        XCTAssertTrue(logger.recordedLevels.contains(.error))
        XCTAssertTrue(logger.recordedEntries.contains { $0.message.contains("readFailed") })
    }

    func testContainsFailureIsLoggedAndReturnsFalse() {
        client.failOnRead = .readFailed(status: -1)

        XCTAssertFalse(storage.contains("token"))

        XCTAssertTrue(logger.recordedLevels.contains(.error))
        XCTAssertTrue(logger.recordedEntries.contains { $0.message.contains("contains check failed") })
    }

    func testDeleteFailurePropagates() throws {
        try storage.setString("value", forKey: "token")
        client.failOnDelete = .deleteFailed(status: -3)

        XCTAssertThrowsError(try storage.remove(forKey: "token")) { error in
            XCTAssertEqual(error as? SecureStorageError, .deleteFailed(status: -3))
        }
    }

    func testConcurrentReadsAndWrites() {
        guard let storage else {
            return XCTFail("Storage was not initialized.")
        }

        let failures = ThreadSafeBox<[String]>([])

        DispatchQueue.concurrentPerform(iterations: 100) { index in
            let key = "key-\(index)"
            let value = "value-\(index)"

            do {
                try storage.setString(value, forKey: key)
                let retrievedValue = try storage.string(forKey: key)
                if retrievedValue != value {
                    failures.mutate { $0.append("Mismatch for \(key).") }
                }
            } catch {
                failures.mutate { $0.append("Error for \(key): \(error)") }
            }
        }

        XCTAssertTrue(failures.current.isEmpty, failures.current.joined(separator: " "))
    }

    func testSystemKeychainRoundTripWhenEnabled() throws {
        guard ProcessInfo.processInfo.environment["SWIFTKIT_RUN_KEYCHAIN_TESTS"] == "1" else {
            throw XCTSkip("Set SWIFTKIT_RUN_KEYCHAIN_TESTS=1 to run real Keychain tests.")
        }

        let service = "com.swiftkit.tests.keychain.\(UUID().uuidString)"
        let keychainStorage = KeychainStorage(service: service, logger: MockLogger())

        do {
            try keychainStorage.setString("value", forKey: "smoke")
            defer { try? keychainStorage.removeAll() }
            XCTAssertEqual(try keychainStorage.string(forKey: "smoke"), "value")
        } catch let error as SecureStorageError {
            switch error {
            case .writeFailed(let status),
                 .updateFailed(let status),
                 .readFailed(let status),
                 .deleteFailed(let status):
                if status == errSecMissingEntitlement
                    || status == errSecInteractionNotAllowed
                    || status == errSecNotAvailable {
                    throw XCTSkip("Keychain unavailable in this environment (OSStatus \(status)).")
                }
                throw error
            default:
                throw error
            }
        }
    }
}
