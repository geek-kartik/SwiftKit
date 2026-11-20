import XCTest
@testable import SampleApp

final class SampleBackendURLProtocolTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        URLProtocol.registerClass(SampleURLProtocol.self)
    }

    override func setUp() async throws {
        try await super.setUp()
        await SampleBackend.shared.reset()
    }

    func testItemsEndpointReturnsDecodableJSON() async throws {
        let url = try XCTUnwrap(URL(string: "https://sample.swiftkit.test/v1/items"))
        let (data, response) = try await URLSession.shared.data(from: url)

        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let decoded = try JSONDecoder().decode(SampleAPIResponse.self, from: data)
        XCTAssertEqual(decoded.status, "ok")
        XCTAssertEqual(decoded.path, "/v1/items")
    }

    func testProtectedEndpointRequiresRefreshedToken() async throws {
        let url = try XCTUnwrap(URL(string: "https://sample.swiftkit.test/v1/protected"))

        let unauthorized = try await URLSession.shared.data(from: url)
        XCTAssertEqual((unauthorized.1 as? HTTPURLResponse)?.statusCode, 401)

        var refresh = URLRequest(url: try XCTUnwrap(URL(string: "https://sample.swiftkit.test/v1/auth/refresh")))
        refresh.httpMethod = "POST"
        refresh.httpBody = try JSONEncoder().encode(SampleRefreshRequest(refreshToken: "test_refresh"))
        let direct = await SampleBackend.shared.handle(refresh)
        XCTAssertEqual(direct.statusCode, 200)
        let refreshed = try await URLSession.shared.data(for: refresh)
        XCTAssertEqual((refreshed.1 as? HTTPURLResponse)?.statusCode, 200)
        let tokens = try JSONDecoder().decode(SampleRefreshResponse.self, from: refreshed.0)

        var authorized = URLRequest(url: url)
        authorized.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
        let success = try await URLSession.shared.data(for: authorized)
        XCTAssertEqual((success.1 as? HTTPURLResponse)?.statusCode, 200)
    }

    func testFailureEndpointReturnsHTTP500() async throws {
        let url = try XCTUnwrap(URL(string: "https://sample.swiftkit.test/v1/failure"))
        let (_, response) = try await URLSession.shared.data(from: url)

        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 500)
    }

    func testNotFoundEndpointReturnsHTTP404() async throws {
        let url = try XCTUnwrap(URL(string: "https://sample.swiftkit.test/v1/not-found"))
        let (data, response) = try await URLSession.shared.data(from: url)

        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 404)
        let decoded = try JSONDecoder().decode(SampleAPIResponse.self, from: data)
        XCTAssertEqual(decoded.message, "Resource not found.")
    }
}
