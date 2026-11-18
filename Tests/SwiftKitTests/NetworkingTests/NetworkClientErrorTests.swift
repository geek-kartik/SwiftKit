import XCTest
@testable import SwiftKit

private struct SecretPayload: Codable, Sendable {
    let accountNumber: String
}

final class NetworkClientErrorTests: XCTestCase {
    private let url = URL(string: "https://api.example.com/v1/accounts")!

    func testTransportTimeoutMapsToTimeout() async {
        let test = makeTestNetworkClient { _ in
            throw URLError(.timedOut)
        }

        let error = await captureNetworkError {
            _ = try await test.client.send(NetworkRequest(url: self.url))
        }

        XCTAssertEqual(error, .timeout)
    }

    func testTransportCancelledMapsToCancelled() async {
        let test = makeTestNetworkClient { _ in
            throw URLError(.cancelled)
        }

        let error = await captureNetworkError {
            _ = try await test.client.send(NetworkRequest(url: self.url))
        }

        XCTAssertEqual(error, .cancelled)
    }

    func testTransportOfflineMapsToNoInternetConnection() async {
        for code in [URLError.Code.notConnectedToInternet, .networkConnectionLost] {
            let test = makeTestNetworkClient { _ in
                throw URLError(code)
            }

            let error = await captureNetworkError {
                _ = try await test.client.send(NetworkRequest(url: URL(string: "https://api.example.com")!))
            }

            XCTAssertEqual(error, .noInternetConnection)
        }
    }

    func testTransportURLErrorMapsToTransportFailure() async {
        let test = makeTestNetworkClient { _ in
            throw URLError(.cannotConnectToHost)
        }

        let error = await captureNetworkError {
            _ = try await test.client.send(NetworkRequest(url: URL(string: "https://api.example.com")!))
        }

        XCTAssertEqual(error, .transportFailure(code: .cannotConnectToHost))
    }

    func testNonURLErrorMapsToUnknownTransportFailure() async {
        let test = makeTestNetworkClient { _ in
            throw NSError(domain: "Test", code: 42)
        }

        let error = await captureNetworkError {
            _ = try await test.client.send(NetworkRequest(url: URL(string: "https://api.example.com")!))
        }

        XCTAssertEqual(error, .transportFailure(code: .unknown))
    }

    func testCancelledTaskThrowsCancelledWithoutSending() async {
        let transport = MockHTTPTransport { request in
            (Data(), makeHTTPResponse(url: request.url!, statusCode: 200))
        }
        let client = URLSessionNetworkClient(
            configuration: NetworkConfiguration(),
            logger: MockLogger(),
            transport: transport
        )

        let task = Task { () -> NetworkResponse in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await client.send(NetworkRequest(url: URL(string: "https://api.example.com")!))
        }

        do {
            _ = try await task.value
            XCTFail("Expected the cancelled task to throw.")
        } catch {
            XCTAssertEqual(error as? NetworkError, .cancelled)
        }

        XCTAssertTrue(transport.requests.isEmpty)
    }

    // MARK: - Logging

    func testSuccessIsLoggedWithoutSensitiveData() async throws {
        let secretURL = URL(string: "https://api.example.com/v1/accounts?access_token=url-secret-token")!
        let test = makeTestNetworkClient { request in
            (Data(), makeHTTPResponse(url: request.url!, statusCode: 200))
        }

        let request = NetworkRequest(
            url: secretURL,
            method: .post,
            headers: ["Authorization": "Bearer header-secret-token"],
            body: Data(#"{"accountNumber":"body-secret"}"#.utf8)
        )
        _ = try await test.client.send(request)

        let messages = test.logger.recordedEntries.map(\.message).joined(separator: " ")

        XCTAssertTrue(test.logger.recordedLevels.contains(.info))
        XCTAssertTrue(messages.contains("api.example.com"))
        XCTAssertTrue(messages.contains("200"))
        XCTAssertFalse(messages.contains("url-secret-token"))
        XCTAssertFalse(messages.contains("header-secret-token"))
        XCTAssertFalse(messages.contains("body-secret"))
    }

    func testHTTPFailureIsLoggedWithoutSensitiveData() async {
        let secretURL = URL(string: "https://api.example.com/v1/accounts?access_token=url-secret-token")!
        let test = makeTestNetworkClient { request in
            (
                Data(#"{"error":"response-secret"}"#.utf8),
                makeHTTPResponse(url: request.url!, statusCode: 500)
            )
        }

        let request = NetworkRequest(
            url: secretURL,
            method: .post,
            headers: ["Authorization": "Bearer header-secret-token"],
            body: Data(#"{"accountNumber":"body-secret"}"#.utf8)
        )
        _ = await captureNetworkError { _ = try await test.client.send(request) }

        let messages = test.logger.recordedEntries.map(\.message).joined(separator: " ")

        XCTAssertTrue(test.logger.recordedLevels.contains(.warning))
        XCTAssertTrue(messages.contains("api.example.com"))
        XCTAssertTrue(messages.contains("500"))
        XCTAssertFalse(messages.contains("url-secret-token"))
        XCTAssertFalse(messages.contains("header-secret-token"))
        XCTAssertFalse(messages.contains("body-secret"))
        XCTAssertFalse(messages.contains("response-secret"))
    }

    func testTransportFailureIsLoggedWithoutSensitiveData() async {
        let secretURL = URL(string: "https://api.example.com/v1/accounts?access_token=url-secret-token")!

        for code in [URLError.Code.timedOut, .cannotConnectToHost] {
            let test = makeTestNetworkClient { _ in
                throw URLError(code)
            }

            _ = await captureNetworkError {
                _ = try await test.client.send(NetworkRequest(url: secretURL))
            }

            let messages = test.logger.recordedEntries.map(\.message).joined(separator: " ")

            XCTAssertTrue(test.logger.recordedLevels.contains(.error))
            XCTAssertTrue(messages.contains("failed"))
            XCTAssertFalse(messages.contains("url-secret-token"))
        }
    }

    func testInvalidResponseIsLoggedAsError() async {
        let test = makeTestNetworkClient { request in
            (
                Data(),
                URLResponse(
                    url: request.url!,
                    mimeType: nil,
                    expectedContentLength: 0,
                    textEncodingName: nil
                )
            )
        }

        _ = await captureNetworkError { _ = try await test.client.send(NetworkRequest(url: url)) }

        XCTAssertTrue(test.logger.recordedLevels.contains(.error))
        XCTAssertTrue(
            test.logger.recordedEntries.contains { $0.message.contains("invalidResponse") }
        )
    }

    // MARK: - Helpers

    private func captureNetworkError(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () async throws -> Void
    ) async -> NetworkError? {
        do {
            try await operation()
            XCTFail("Expected a NetworkError to be thrown.", file: file, line: line)
            return nil
        } catch let error as NetworkError {
            return error
        } catch {
            XCTFail("Expected a NetworkError, got \(error).", file: file, line: line)
            return nil
        }
    }
}
