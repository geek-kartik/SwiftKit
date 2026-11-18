import XCTest
@testable import SwiftKit

private struct JSONBody: Encodable {
    let accountNumber: String
}

private struct NonFiniteBody: Encodable {
    let value: Double
}

final class NetworkRequestTests: XCTestCase {
    private let url = URL(string: "https://api.bank.example/v1/accounts")!

    // MARK: - HTTP Methods

    func testHTTPMethodRawValues() {
        XCTAssertEqual(HTTPMethod.get.rawValue, "GET")
        XCTAssertEqual(HTTPMethod.post.rawValue, "POST")
        XCTAssertEqual(HTTPMethod.put.rawValue, "PUT")
        XCTAssertEqual(HTTPMethod.patch.rawValue, "PATCH")
        XCTAssertEqual(HTTPMethod.delete.rawValue, "DELETE")
        XCTAssertEqual(HTTPMethod.allCases.count, 5)
    }

    func testOnlyGETDisallowsRequestBody() {
        XCTAssertFalse(HTTPMethod.get.allowsRequestBody)

        for method in HTTPMethod.allCases where method != .get {
            XCTAssertTrue(method.allowsRequestBody)
        }
    }

    // MARK: - Initializers

    func testDefaultRequestValues() {
        let request = NetworkRequest(url: url)

        XCTAssertEqual(request.url, url)
        XCTAssertEqual(request.method, .get)
        XCTAssertTrue(request.headers.isEmpty)
        XCTAssertNil(request.body)
        XCTAssertNil(request.timeoutInterval)
        XCTAssertNil(request.cachePolicy)
    }

    func testRequestStoresSuppliedValues() {
        let body = Data("payload".utf8)
        let request = NetworkRequest(
            url: url,
            method: .patch,
            headers: ["X-Request-ID": "abc"],
            body: body,
            timeoutInterval: 10,
            cachePolicy: .reloadIgnoringLocalCacheData
        )

        XCTAssertEqual(request.url, url)
        XCTAssertEqual(request.method, .patch)
        XCTAssertEqual(request.headers, ["X-Request-ID": "abc"])
        XCTAssertEqual(request.body, body)
        XCTAssertEqual(request.timeoutInterval, 10)
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
    }

    func testPathInitializerBuildsRelativeURL() throws {
        let request = try NetworkRequest(path: "/v1/accounts", method: .get)

        XCTAssertNil(request.url.scheme)
        XCTAssertEqual(request.url.relativeString, "/v1/accounts")
        XCTAssertEqual(request.method, .get)
    }

    func testPathInitializerAppendsQueryItems() throws {
        let request = try NetworkRequest(
            path: "/v1/accounts?status=active",
            queryItems: [
                URLQueryItem(name: "page", value: "2"),
                URLQueryItem(name: "limit", value: "50")
            ]
        )

        let components = URLComponents(url: request.url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []

        XCTAssertEqual(queryItems.first { $0.name == "status" }?.value, "active")
        XCTAssertEqual(queryItems.first { $0.name == "page" }?.value, "2")
        XCTAssertEqual(queryItems.first { $0.name == "limit" }?.value, "50")
    }

    func testPathInitializerEncodesQueryValues() throws {
        let request = try NetworkRequest(
            path: "/v1/search",
            queryItems: [URLQueryItem(name: "query", value: "john doe & co")]
        )

        XCTAssertTrue(request.url.absoluteString.contains("john%20doe%20%26%20co"))
    }

    func testPathInitializerThrowsForMalformedPath() {
        XCTAssertThrowsError(try NetworkRequest(path: "https://[::1")) { error in
            XCTAssertEqual(error as? NetworkError, .invalidURL)
        }
    }

    // MARK: - Headers

    func testHeaderLookupIsCaseInsensitive() {
        let request = NetworkRequest(url: url, headers: ["Content-Type": "application/json"])

        XCTAssertEqual(request.header(named: "content-type"), "application/json")
        XCTAssertEqual(request.header(named: "CONTENT-TYPE"), "application/json")
    }

    func testHeaderLookupReturnsNilForMissingHeader() {
        XCTAssertNil(NetworkRequest(url: url).header(named: "Authorization"))
    }

    func testWithHeaderAddsHeader() {
        let request = NetworkRequest(url: url).withHeader("Authorization", value: "Bearer token")

        XCTAssertEqual(request.header(named: "authorization"), "Bearer token")
    }

    func testWithHeaderReplacesCaseInsensitiveMatch() {
        let request = NetworkRequest(url: url, headers: ["authorization": "old"])
            .withHeader("Authorization", value: "new")

        XCTAssertEqual(request.header(named: "Authorization"), "new")
        XCTAssertEqual(request.headers.count, 1)
    }

    func testWithHeadersAppliesAllHeaders() {
        let request = NetworkRequest(url: url)
            .withHeaders(["Accept": "application/json", "X-Trace-ID": "trace-1"])

        XCTAssertEqual(request.header(named: "accept"), "application/json")
        XCTAssertEqual(request.header(named: "x-trace-id"), "trace-1")
    }

    // MARK: - JSON Body

    func testWithJSONBodyEncodesBodyAndSetsContentType() throws {
        let request = try NetworkRequest(url: url, method: .post)
            .withJSONBody(JSONBody(accountNumber: "12345678"))

        XCTAssertEqual(request.body, Data(#"{"accountNumber":"12345678"}"#.utf8))
        XCTAssertEqual(request.header(named: "Content-Type"), "application/json")
    }

    func testWithJSONBodyPreservesExplicitContentType() throws {
        let request = try NetworkRequest(
            url: url,
            method: .post,
            headers: ["content-type": "application/vnd.api+json"]
        )
        .withJSONBody(JSONBody(accountNumber: "12345678"))

        XCTAssertEqual(request.header(named: "Content-Type"), "application/vnd.api+json")
        XCTAssertEqual(request.headers.count, 1)
    }

    func testWithJSONBodyUsesSuppliedEncoder() throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase

        let request = try NetworkRequest(url: url, method: .post)
            .withJSONBody(JSONBody(accountNumber: "12345678"), using: encoder)

        XCTAssertEqual(request.body, Data(#"{"account_number":"12345678"}"#.utf8))
    }

    func testWithJSONBodyThrowsEncodingFailedForNonFiniteValue() {
        let request = NetworkRequest(url: url, method: .post)

        XCTAssertThrowsError(try request.withJSONBody(NonFiniteBody(value: .nan))) { error in
            XCTAssertEqual(error as? NetworkError, .encodingFailed)
        }
    }

    func testWithJSONBodyPreservesMethodAndTimeout() throws {
        let request = try NetworkRequest(url: url, method: .put, timeoutInterval: 12)
            .withJSONBody(JSONBody(accountNumber: "123"))

        XCTAssertEqual(request.method, .put)
        XCTAssertEqual(request.timeoutInterval, 12)
    }
}
