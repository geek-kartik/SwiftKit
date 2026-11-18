import XCTest
@testable import SwiftKit

/// Tests for the copy-as-cURL export of a captured transaction.
final class NetworkCurlTests: XCTestCase {
    private let url = URL(string: "https://api.bank.example/v1/accounts/acc-1?expand=transactions")!

    func testCommandContainsMethodURLHeadersAndBody() {
        let transaction = makeTransaction(
            method: .patch,
            headers: [
                "Content-Type": "application/json",
                "Accept": "application/json"
            ],
            body: Data(#"{"nickname":"Daily driver"}"#.utf8)
        )

        let command = transaction.curlCommand

        XCTAssertTrue(command.hasPrefix("curl -X PATCH 'https://api.bank.example/v1/accounts/acc-1?expand=transactions'"))
        XCTAssertTrue(command.contains("-H 'Accept: application/json'"))
        XCTAssertTrue(command.contains("-H 'Content-Type: application/json'"))
        XCTAssertTrue(command.contains("--data-raw '{\"nickname\":\"Daily driver\"}'"))
    }

    func testHeadersAreSortedCaseInsensitively() {
        let transaction = makeTransaction(
            headers: ["b-header": "2", "A-Header": "1", "c-header": "3"]
        )

        let command = transaction.curlCommand
        let a = command.range(of: "A-Header")!.lowerBound
        let b = command.range(of: "b-header")!.lowerBound
        let c = command.range(of: "c-header")!.lowerBound

        XCTAssertTrue(a < b)
        XCTAssertTrue(b < c)
    }

    func testCredentialHeadersAreRedactedByDefault() {
        let transaction = makeTransaction(
            headers: [
                "Authorization": "Bearer super-secret",
                "X-Api-Key": "key-123",
                "Accept": "application/json"
            ]
        )

        let command = transaction.curlCommand

        XCTAssertTrue(command.contains("-H 'Authorization: [REDACTED]'"))
        XCTAssertTrue(command.contains("-H 'X-Api-Key: [REDACTED]'"))
        XCTAssertTrue(command.contains("-H 'Accept: application/json'"))
        XCTAssertFalse(command.contains("super-secret"))
        XCTAssertFalse(command.contains("key-123"))
    }

    func testIncludePolicyExportsCredentialHeaders() {
        let transaction = makeTransaction(
            headers: ["Authorization": "Bearer super-secret"]
        )

        let command = transaction.curlCommand(sensitiveDataPolicy: .include)

        XCTAssertTrue(command.contains("-H 'Authorization: Bearer super-secret'"))
        XCTAssertFalse(command.contains("[REDACTED]"))
    }

    func testSingleQuotesAreShellEscaped() {
        let transaction = makeTransaction(
            method: .post,
            headers: ["X-Note": "it's fine"],
            body: Data(#"{"note":"don't stop"}"#.utf8)
        )

        let command = transaction.curlCommand(sensitiveDataPolicy: .include)

        XCTAssertTrue(command.contains(#"-H 'X-Note: it'\''s fine'"#))
        XCTAssertTrue(command.contains(#"--data-raw '{"note":"don'\''t stop"}'"#))
    }

    func testGetWithoutBodyOmitsDataFlag() {
        let transaction = makeTransaction(method: .get)

        let command = transaction.curlCommand

        XCTAssertTrue(command.hasPrefix("curl -X GET"))
        XCTAssertFalse(command.contains("--data-raw"))
        XCTAssertFalse(command.contains("\\\n"))
    }

    func testTruncatedBodyIsAnnotated() {
        let inspector = NetworkInspector(
            configuration: NetworkInspectorConfiguration(isEnabled: true, maxBodyBytes: 5)
        )
        let transaction = NetworkTransaction(
            startedAt: Date(),
            duration: 0.01,
            request: NetworkTransaction.Request(
                method: .post,
                url: url,
                body: .init(data: Data("0123456789".utf8))
            )
        )
        inspector.record(transaction)

        let command = try! XCTUnwrap(inspector.transactions.first).curlCommand

        XCTAssertTrue(command.hasPrefix("# Request body truncated: showing 5 of 10 bytes."))
        XCTAssertTrue(command.contains("--data-raw '01234'"))
    }

    func testBinaryBodyIsOmittedWithAnnotation() {
        let transaction = makeTransaction(
            method: .post,
            body: Data([0xFF, 0xFE, 0x00, 0x01])
        )

        let command = transaction.curlCommand

        XCTAssertTrue(command.contains("# Request body is not UTF-8 text and was omitted from this command."))
        XCTAssertFalse(command.contains("--data-raw"))
    }

    func testEmptyBodyDoesNotEmitDataFlag() {
        let transaction = makeTransaction(method: .post, body: Data())

        let command = transaction.curlCommand

        XCTAssertFalse(command.contains("--data-raw"))
        XCTAssertFalse(command.contains("truncated"))
    }

    func testMalformedURLCannotBeExported() {
        let transaction = NetworkTransaction(
            startedAt: Date(),
            duration: 0,
            request: NetworkTransaction.Request(method: .get, url: URL(string: "/relative")!)
        )

        // The command still renders for diagnostics, but the UI disables copying because the
        // URL has no scheme.
        XCTAssertEqual(transaction.curlCommand, "curl -X GET '/relative'")
        XCTAssertNil(transaction.request.url.scheme)
    }

    // MARK: - Helpers

    private func makeTransaction(
        method: HTTPMethod = .get,
        headers: [String: String] = [:],
        body: Data? = nil
    ) -> NetworkTransaction {
        NetworkTransaction(
            startedAt: Date(),
            duration: 0.02,
            request: NetworkTransaction.Request(
                method: method,
                url: url,
                headers: headers,
                body: body.map { NetworkTransaction.Body(data: $0) }
            )
        )
    }
}
