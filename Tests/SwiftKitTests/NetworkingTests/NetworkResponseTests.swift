import XCTest
@testable import SwiftKit

private struct Account: Codable, Equatable, Sendable {
    let identifier: String
    let displayName: String
}

private struct SnakeCaseAccount: Decodable, Equatable {
    let accountId: String
}

final class NetworkResponseTests: XCTestCase {
    func testIsSuccessForTwoHundredRange() {
        XCTAssertTrue(makeResponse(statusCode: 200).isSuccess)
        XCTAssertTrue(makeResponse(statusCode: 201).isSuccess)
        XCTAssertTrue(makeResponse(statusCode: 204).isSuccess)
        XCTAssertTrue(makeResponse(statusCode: 299).isSuccess)
    }

    func testIsSuccessFalseOutsideTwoHundredRange() {
        XCTAssertFalse(makeResponse(statusCode: 199).isSuccess)
        XCTAssertFalse(makeResponse(statusCode: 300).isSuccess)
        XCTAssertFalse(makeResponse(statusCode: 400).isSuccess)
        XCTAssertFalse(makeResponse(statusCode: 500).isSuccess)
    }

    func testHeaderLookupIsCaseInsensitive() {
        let response = NetworkResponse(
            statusCode: 200,
            headers: ["X-Request-ID": "abc"],
            data: Data()
        )

        XCTAssertEqual(response.header(named: "x-request-id"), "abc")
        XCTAssertNil(response.header(named: "Missing"))
    }

    func testDecodeValidJSON() throws {
        let response = NetworkResponse(
            statusCode: 200,
            data: Data(#"{"identifier":"acc_1","displayName":"Archana"}"#.utf8)
        )

        let account = try response.decode(Account.self)

        XCTAssertEqual(account, Account(identifier: "acc_1", displayName: "Archana"))
    }

    func testDecodeWithCustomDecoder() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = NetworkResponse(statusCode: 200, data: Data(#"{"account_id":"acc_1"}"#.utf8))

        let account = try response.decode(SnakeCaseAccount.self, using: decoder)

        XCTAssertEqual(account, SnakeCaseAccount(accountId: "acc_1"))
    }

    func testDecodeThrowsEmptyResponseForEmptyData() {
        let response = NetworkResponse(statusCode: 204, data: Data())

        XCTAssertThrowsError(try response.decode(Account.self)) { error in
            XCTAssertEqual(error as? NetworkError, .emptyResponse)
        }
    }

    func testDecodeThrowsDecodingFailedForMalformedJSON() {
        let response = NetworkResponse(statusCode: 200, data: Data("not-json".utf8))

        XCTAssertThrowsError(try response.decode(Account.self)) { error in
            XCTAssertEqual(error as? NetworkError, .decodingFailed)
        }
    }

    func testDecodeThrowsDecodingFailedForTypeMismatch() {
        let response = NetworkResponse(statusCode: 200, data: Data(#"{"identifier":42}"#.utf8))

        XCTAssertThrowsError(try response.decode(Account.self)) { error in
            XCTAssertEqual(error as? NetworkError, .decodingFailed)
        }
    }

    func testDecodeThrowsDecodingFailedForMissingField() {
        let response = NetworkResponse(statusCode: 200, data: Data(#"{"identifier":"acc_1"}"#.utf8))

        XCTAssertThrowsError(try response.decode(Account.self)) { error in
            XCTAssertEqual(error as? NetworkError, .decodingFailed)
        }
    }

    func testEqualityComparesAllStoredValues() {
        let url = URL(string: "https://api.bank.example")!
        let first = NetworkResponse(statusCode: 200, headers: ["A": "B"], data: Data([1]), url: url)
        let second = NetworkResponse(statusCode: 200, headers: ["A": "B"], data: Data([1]), url: url)

        XCTAssertEqual(first, second)
        XCTAssertNotEqual(first, NetworkResponse(statusCode: 201, headers: ["A": "B"], data: Data([1]), url: url))
    }

    private func makeResponse(statusCode: Int) -> NetworkResponse {
        NetworkResponse(statusCode: statusCode, data: Data())
    }
}
