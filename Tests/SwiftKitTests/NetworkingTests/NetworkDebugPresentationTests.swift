import XCTest
@testable import SwiftKit

/// Tests for the text the network debugger renders for status codes, bodies, and rows.
final class NetworkDebugPresentationTests: XCTestCase {
    // MARK: - Status and size text

    func testStatusLineUsesReasonPhrase() {
        XCTAssertEqual(HTTPStatusText.statusLine(200), "200 OK")
        XCTAssertEqual(HTTPStatusText.statusLine(401), "401 Unauthorized")
        XCTAssertEqual(HTTPStatusText.statusLine(500), "500 Internal Server Error")
    }

    func testUnknownStatusCodeFallsBackToUnknown() {
        XCTAssertEqual(HTTPStatusText.statusLine(599), "599 Unknown")
    }

    func testByteCountUsesReadableUnits() {
        XCTAssertEqual(HTTPStatusText.byteCount(0), "0 B")
        XCTAssertEqual(HTTPStatusText.byteCount(1_023), "1023 B")
        XCTAssertEqual(HTTPStatusText.byteCount(1_024), "1.0 KB")
        XCTAssertEqual(HTTPStatusText.byteCount(1_048_576), "1.0 MB")
    }

    func testMillisecondsRoundsToWholeMilliseconds() {
        XCTAssertEqual(HTTPStatusText.milliseconds(0), "0 ms")
        XCTAssertEqual(HTTPStatusText.milliseconds(0.0424), "42 ms")
        XCTAssertEqual(HTTPStatusText.milliseconds(1.5), "1500 ms")
    }

    // MARK: - JSON formatting

    func testPrettyPrintPreservesNumberLiterals() {
        let json = #"{"amount":58210.4,"ok":true}"#

        let formatted = JSONTextFormatter.prettyPrinted(json)

        XCTAssertEqual(
            formatted,
            """
            {
              "amount": 58210.4,
              "ok": true
            }
            """
        )
    }

    func testPrettyPrintHandlesNestedObjectsAndArrays() {
        let json = #"{"a":[1,{"b":2}]}"#

        let formatted = JSONTextFormatter.prettyPrinted(json)

        XCTAssertEqual(
            formatted,
            """
            {
              "a": [
                1,
                {
                  "b": 2
                }
              ]
            }
            """
        )
    }

    func testPrettyPrintKeepsEscapedQuotesInsideStrings() {
        let json = #"{"quote":"say \"hi\""}"#

        let formatted = JSONTextFormatter.prettyPrinted(json)

        XCTAssertEqual(
            formatted,
            #"""
            {
              "quote": "say \"hi\""
            }
            """#
        )
    }

    func testDisplayTextPrettyPrintsJSONBodies() {
        let data = Data(#"{"status":"ok"}"#.utf8)

        XCTAssertEqual(JSONTextFormatter.displayText(from: data), "{\n  \"status\": \"ok\"\n}")
    }

    func testDisplayTextLeavesNonJSONTextUntouched() {
        let data = Data("plain text".utf8)

        XCTAssertEqual(JSONTextFormatter.displayText(from: data), "plain text")
    }

    func testDisplayTextFallsBackWhenJSONIsUnbalanced() {
        let data = Data(#"{"a":1"#.utf8)

        XCTAssertEqual(JSONTextFormatter.displayText(from: data), #"{"a":1"#)
    }

    func testDisplayTextReturnsNilForBinaryBodies() {
        XCTAssertNil(JSONTextFormatter.displayText(from: Data([0xFF, 0xFE])))
    }

    func testPrettyPrintRejectsUnbalancedInput() {
        XCTAssertNil(JSONTextFormatter.prettyPrinted(#"{"a":1"#))
        XCTAssertNil(JSONTextFormatter.prettyPrinted(#"{"a":1}}"#))
        XCTAssertNil(JSONTextFormatter.prettyPrinted(#"{"a":"unterminated}"#))
    }

    // MARK: - Inspector row text

    func testPathTextIncludesQueryString() {
        let transaction = makeTransaction(url: "https://api.example.com/v1/accounts?limit=1")

        XCTAssertEqual(transaction.pathText, "/v1/accounts?limit=1")
    }

    func testPathTextFallsBackToTheAbsoluteURLWhenPathIsEmpty() {
        let transaction = makeTransaction(url: "https://api.example.com")

        XCTAssertEqual(transaction.pathText, "https://api.example.com")
    }

    func testDurationTextRoundsToMilliseconds() {
        let transaction = makeTransaction(url: "https://api.example.com/health", duration: 0.0424)

        XCTAssertEqual(transaction.durationText, "42 ms")
    }

    func testStatusCodeComesFromHTTPStatusError() {
        let response = NetworkResponse(statusCode: 503, data: Data())
        let transaction = NetworkTransaction(
            startedAt: Date(),
            duration: 0.01,
            request: NetworkTransaction.Request(
                method: .get,
                url: URL(string: "https://api.example.com/v1/accounts")!
            ),
            response: nil,
            error: .httpStatus(response)
        )

        XCTAssertEqual(transaction.statusCode, 503)
        XCTAssertEqual(transaction.errorDescription, "The server returned an unacceptable HTTP status code: 503.")
        XCTAssertFalse(transaction.isSuccess)
    }

    func testSuccessClassificationRequiresAResponseWithoutError() {
        let success = makeTransaction(
            url: "https://api.example.com/health",
            response: NetworkTransaction.Response(statusCode: 200, body: .init(data: Data())),
            error: nil
        )
        let failure = makeTransaction(
            url: "https://api.example.com/health",
            response: nil,
            error: .timeout
        )
        let incomplete = makeTransaction(
            url: "https://api.example.com/health",
            response: nil,
            error: nil
        )

        XCTAssertTrue(success.isSuccess)
        XCTAssertFalse(failure.isSuccess)
        XCTAssertFalse(incomplete.isSuccess)
    }

    // MARK: - Helpers

    private func makeTransaction(
        url: String,
        duration: TimeInterval = 0.042,
        response: NetworkTransaction.Response? = NetworkTransaction.Response(
            statusCode: 200,
            body: .init(data: Data())
        ),
        error: NetworkError? = nil
    ) -> NetworkTransaction {
        NetworkTransaction(
            startedAt: Date(timeIntervalSince1970: 0),
            duration: duration,
            request: NetworkTransaction.Request(method: .get, url: URL(string: url)!),
            response: response,
            error: error
        )
    }
}
