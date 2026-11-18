import XCTest
import SwiftKit
@testable import SampleApp

@MainActor
final class SecureStorageViewModelTests: XCTestCase {
    private var mockStorage: MockSecureStorage!
    private var mockLogger: MockLogger!
    private var viewModel: SecureStorageViewModel!

    override func setUp() {
        super.setUp()
        mockStorage = MockSecureStorage()
        mockLogger = MockLogger()
        viewModel = SecureStorageViewModel(secureStorage: mockStorage, logger: mockLogger)
    }

    override func tearDown() {
        viewModel = nil
        mockStorage = nil
        mockLogger = nil
        super.tearDown()
    }

    func testSaveAndReadStringSuccess() {
        viewModel.inputKey = "authToken"
        viewModel.inputValue = "secret_value_123"

        viewModel.saveString()

        XCTAssertFalse(viewModel.isErrorMessage)
        XCTAssertTrue(viewModel.statusMessage.contains("Successfully saved"))
        XCTAssertEqual(viewModel.containsKeyResult, true)

        viewModel.inputValue = ""
        viewModel.readString()

        XCTAssertEqual(viewModel.retrievedValue, "secret_value_123")
        XCTAssertFalse(viewModel.isErrorMessage)
    }

    func testReadMissingKeyShowsErrorFeedback() {
        viewModel.inputKey = "nonExistentKey"
        viewModel.readString()

        XCTAssertTrue(viewModel.isErrorMessage)
        XCTAssertTrue(viewModel.retrievedValue.isEmpty)
        XCTAssertTrue(viewModel.statusMessage.contains("No secure storage item was found"))
    }

    func testEmptyKeyValidation() {
        viewModel.inputKey = ""
        viewModel.inputValue = "test"

        viewModel.saveString()

        XCTAssertTrue(viewModel.isErrorMessage)
        XCTAssertEqual(viewModel.statusMessage, "Key cannot be empty.")
    }

    func testUpdateStringOverwritesValue() {
        viewModel.inputKey = "token"
        viewModel.inputValue = "original"
        viewModel.saveString()

        viewModel.inputValue = "updated"
        viewModel.updateString()

        viewModel.readString()
        XCTAssertEqual(viewModel.retrievedValue, "updated")
    }

    func testRemoveKeyDeletesValue() {
        viewModel.inputKey = "tempKey"
        viewModel.inputValue = "tempValue"
        viewModel.saveString()

        viewModel.removeKey()

        XCTAssertFalse(viewModel.isErrorMessage)
        XCTAssertEqual(viewModel.containsKeyResult, false)
        XCTAssertTrue(viewModel.retrievedValue.isEmpty)

        viewModel.readString()
        XCTAssertTrue(viewModel.isErrorMessage)
    }

    func testCodableProfileRoundTrip() {
        viewModel.profileUserId = "user_99"
        viewModel.profileUsername = "alice"
        viewModel.profileRole = "Engineer"

        viewModel.saveProfile(key: "test_profile_key")
        XCTAssertFalse(viewModel.isErrorMessage)

        viewModel.readProfile(key: "test_profile_key")
        XCTAssertNotNil(viewModel.retrievedProfile)
        XCTAssertEqual(viewModel.retrievedProfile?.userId, "user_99")
        XCTAssertEqual(viewModel.retrievedProfile?.username, "alice")
        XCTAssertEqual(viewModel.retrievedProfile?.role, "Engineer")
    }

    func testDataPersistenceRoundTrip() {
        viewModel.testDataPersistence(key: "test_raw_key")
        XCTAssertFalse(viewModel.isErrorMessage)
        XCTAssertTrue(viewModel.statusMessage.contains("8 bytes"))
    }

    func testClearAllStorageRemovesAllItems() {
        viewModel.inputKey = "key1"
        viewModel.inputValue = "val1"
        viewModel.saveString()

        viewModel.clearAllStorage()

        XCTAssertFalse(viewModel.isErrorMessage)
        XCTAssertEqual(viewModel.containsKeyResult, false)
        XCTAssertFalse(mockStorage.contains("key1"))
    }
}
