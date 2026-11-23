import XCTest
@testable import SwiftKit

private struct AccountPayload: Codable, Equatable, Sendable {
    let identifier: String
}

private struct SnakeCaseAccount: Decodable, Equatable {
    let accountId: String
}

private struct POSTBody: Encodable, Sendable {
    let accountNumber: String
}

private struct NonFiniteBody: Encodable, Sendable {
    let value: Double
}

/// Coordinates test requests so multiple transports are in flight at the same time.
private actor ConcurrencyGate {
    private var expectedArrivals = 0
    private var arrivals = 0
    private var arrivalContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuations: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false

    func expect(_ count: Int) {
        expectedArrivals = count
    }

    func arriveAndWait() async {
        arrivals += 1
        if arrivals >= expectedArrivals {
            arrivalContinuation?.resume()
            arrivalContinuation = nil
        }

        if isOpen { return }
        await withCheckedContinuation { releaseContinuations.append($0) }
    }

    func waitForArrivals() async {
        guard arrivals < expectedArrivals else { return }
        await withCheckedContinuation { arrivalContinuation = $0 }
    }

    func open() {
        isOpen = true
        let continuations = releaseContinuations
        releaseContinuations.removeAll()
        continuations.forEach { $0.resume() }
    }
}

/// Supplies a distinct token per call while requests run concurrently.
private actor TokenSequence {
    private var value = 0

    func next() -> String {
        value += 1
        return "token_\(value)"
    }
}

final class NetworkClientRequestTests: XCTestCase {
    private let baseURL = URL(string: "https://api.example.com")!
    private let url = URL(string: "https://api.example.com/v1/accounts")!

    // MARK: - Successful Requests

    func testSendReturnsResponseForSuccessfulStatus() async throws {
        let data = Data(#"{"identifier":"acc_1"}"#.utf8)
        let test = makeTestNetworkClient { request in
            (data, makeHTTPResponse(url: request.url!, statusCode: 200))
        }

        let response = try await test.client.send(NetworkRequest(url: url))

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(response.data, data)
        XCTAssertTrue(response.isSuccess)
    }

    func testAllHTTPMethodsAreTransmitted() async throws {
        for method in HTTPMethod.allCases {
            let body = method == .get ? nil : Data("payload".utf8)
            let test = makeTestNetworkClient { request in
                (Data(), makeHTTPResponse(url: request.url!, statusCode: 204))
            }

            let request = NetworkRequest(url: url, method: method, body: body)
            _ = try await test.client.send(request)

            XCTAssertEqual(test.transport.lastRequest?.httpMethod, method.rawValue)
            XCTAssertEqual(test.transport.lastRequest?.httpBody, body)
        }
    }

    func testPOSTBodyIsTransmitted() async throws {
        let body = Data(#"{"accountNumber":"12345678"}"#.utf8)
        let test = makeTestNetworkClient { request in
            (Data(), makeHTTPResponse(url: request.url!, statusCode: 201))
        }

        _ = try await test.client.send(NetworkRequest(url: url, method: .post, body: body))

        XCTAssertEqual(test.transport.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(test.transport.lastRequest?.httpBody, body)
    }

    // MARK: - URL Resolution

    func testAbsoluteURLIsUsedAsIs() async throws {
        let test = makeTestNetworkClient(
            configuration: NetworkConfiguration(baseURL: URL(string: "https://other.example.com")!)
        ) { request in
            (Data(), makeHTTPResponse(url: request.url!, statusCode: 200))
        }

        _ = try await test.client.send(NetworkRequest(url: url))

        XCTAssertEqual(test.transport.lastRequest?.url, url)
    }

    func testRelativePathResolvesAgainstBaseURL() async throws {
        let test = makeTestNetworkClient { request in
            (Data(), makeHTTPResponse(url: request.url!, statusCode: 200))
        }

        let request = try NetworkRequest(path: "/v1/accounts")
        _ = try await test.client.send(request)

        XCTAssertEqual(
            test.transport.lastRequest?.url?.absoluteString,
            "https://api.example.com/v1/accounts"
        )
    }

    func testRelativePathPreservesBaseURLPathPrefix() async throws {
        let test = makeTestNetworkClient(
            configuration: NetworkConfiguration(baseURL: URL(string: "https://api.example.com/api/v1")!)
        ) { request in
            (Data(), makeHTTPResponse(url: request.url!, statusCode: 200))
        }

        let request = try NetworkRequest(path: "/accounts")
        _ = try await test.client.send(request)

        XCTAssertEqual(
            test.transport.lastRequest?.url?.absoluteString,
            "https://api.example.com/api/v1/accounts"
        )
    }

    func testRelativePathHandlesTrailingSlashInBaseURL() async throws {
        let test = makeTestNetworkClient(
            configuration: NetworkConfiguration(baseURL: URL(string: "https://api.example.com/api/v1/")!)
        ) { request in
            (Data(), makeHTTPResponse(url: request.url!, statusCode: 200))
        }

        let request = try NetworkRequest(path: "accounts")
        _ = try await test.client.send(request)

        XCTAssertEqual(
            test.transport.lastRequest?.url?.absoluteString,
            "https://api.example.com/api/v1/accounts"
        )
    }

    func testRelativePathPreservesQueryWhenResolving() async throws {
        let test = makeTestNetworkClient(
            configuration: NetworkConfiguration(baseURL: URL(string: "https://api.example.com/api/v1")!)
        ) { request in
            (Data(), makeHTTPResponse(url: request.url!, statusCode: 200))
        }

        let request = try NetworkRequest(path: "/accounts?status=active&page=2")
        _ = try await test.client.send(request)

        XCTAssertEqual(
            test.transport.lastRequest?.url?.absoluteString,
            "https://api.example.com/api/v1/accounts?status=active&page=2"
        )
    }

    func testRelativePathWithoutBaseURLThrowsInvalidURL() async {
        let test = makeTestNetworkClient(configuration: NetworkConfiguration()) { request in
            (Data(), makeHTTPResponse(url: request.url!, statusCode: 200))
        }

        await assertNetworkError(.invalidURL) {
            let request = try NetworkRequest(path: "/v1/accounts")
            _ = try await test.client.send(request)
        }
    }

    func testUnsupportedSchemeThrowsInvalidURL() async {
        let test = makeTestNetworkClient { request in
            (Data(), makeHTTPResponse(url: request.url!, statusCode: 200))
        }

        await assertNetworkError(.invalidURL) {
            _ = try await test.client.send(NetworkRequest(url: URL(string: "ftp://files.example.com/report")!))
        }
    }

    // MARK: - Headers

    func testMergesDefaultAndRequestHeaders() async throws {
        let configuration = NetworkConfiguration(
            baseURL: baseURL,
            defaultHeaders: ["Accept": "application/json", "X-Client": "SwiftKit"]
        )
        let test = makeTestNetworkClient(configuration: configuration) { request in
            (Data(), makeHTTPResponse(url: request.url!, statusCode: 200))
        }

        let request = NetworkRequest(url: url, headers: ["Authorization": "Bearer request-token"])
        _ = try await test.client.send(request)

        XCTAssertEqual(test.transport.lastRequest?.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(test.transport.lastRequest?.value(forHTTPHeaderField: "X-Client"), "SwiftKit")
        XCTAssertEqual(
            test.transport.lastRequest?.value(forHTTPHeaderField: "Authorization"),
            "Bearer request-token"
        )
    }

    func testRequestHeadersOverrideDefaultsCaseInsensitively() async throws {
        let configuration = NetworkConfiguration(
            baseURL: baseURL,
            defaultHeaders: ["Authorization": "Bearer default-token"]
        )
        let test = makeTestNetworkClient(configuration: configuration) { request in
            (Data(), makeHTTPResponse(url: request.url!, statusCode: 200))
        }

        let request = NetworkRequest(url: url, headers: ["authorization": "Bearer request-token"])
        _ = try await test.client.send(request)

        XCTAssertEqual(
            test.transport.lastRequest?.value(forHTTPHeaderField: "Authorization"),
            "Bearer request-token"
        )
    }

    // MARK: - Timeouts and Cache Policy

    func testConfigurationTimeoutIsApplied() async throws {
        let test = makeTestNetworkClient(
            configuration: NetworkConfiguration(baseURL: baseURL, timeoutInterval: 15)
        ) { request in
            (Data(), makeHTTPResponse(url: request.url!, statusCode: 200))
        }

        _ = try await test.client.send(NetworkRequest(url: url))

        XCTAssertEqual(test.transport.lastRequest?.timeoutInterval, 15)
    }

    func testRequestTimeoutOverridesConfiguration() async throws {
        let test = makeTestNetworkClient(
            configuration: NetworkConfiguration(baseURL: baseURL, timeoutInterval: 15)
        ) { request in
            (Data(), makeHTTPResponse(url: request.url!, statusCode: 200))
        }

        _ = try await test.client.send(NetworkRequest(url: url, timeoutInterval: 5))

        XCTAssertEqual(test.transport.lastRequest?.timeoutInterval, 5)
    }

    func testConfigurationCachePolicyIsApplied() async throws {
        let test = makeTestNetworkClient(
            configuration: NetworkConfiguration(baseURL: baseURL, cachePolicy: .reloadIgnoringLocalCacheData)
        ) { request in
            (Data(), makeHTTPResponse(url: request.url!, statusCode: 200))
        }

        _ = try await test.client.send(NetworkRequest(url: url))

        XCTAssertEqual(test.transport.lastRequest?.cachePolicy, .reloadIgnoringLocalCacheData)
    }

    func testRequestCachePolicyOverridesConfiguration() async throws {
        let test = makeTestNetworkClient(
            configuration: NetworkConfiguration(baseURL: baseURL, cachePolicy: .reloadIgnoringLocalCacheData)
        ) { request in
            (Data(), makeHTTPResponse(url: request.url!, statusCode: 200))
        }

        _ = try await test.client.send(NetworkRequest(url: url, cachePolicy: .useProtocolCachePolicy))

        XCTAssertEqual(test.transport.lastRequest?.cachePolicy, .useProtocolCachePolicy)
    }

    // MARK: - Request Validation

    func testGETWithBodyThrowsInvalidRequest() async {
        let test = makeTestNetworkClient { request in
            (Data(), makeHTTPResponse(url: request.url!, statusCode: 200))
        }

        let request = NetworkRequest(url: url, method: .get, body: Data("payload".utf8))

        await assertNetworkError {
            _ = try await test.client.send(request)
        } verify: { error in
            guard case .invalidRequest(let reason) = error else {
                return XCTFail("Expected invalidRequest, got \(error)")
            }
            XCTAssertTrue(reason.contains("GET"))
        }

        XCTAssertTrue(test.transport.requests.isEmpty)
    }

    func testZeroRequestTimeoutThrowsInvalidRequest() async {
        let test = makeTestNetworkClient { request in
            (Data(), makeHTTPResponse(url: request.url!, statusCode: 200))
        }

        await assertNetworkError {
            _ = try await test.client.send(NetworkRequest(url: url, timeoutInterval: 0))
        } verify: { error in
            guard case .invalidRequest = error else {
                return XCTFail("Expected invalidRequest, got \(error)")
            }
        }
    }

    func testNegativeRequestTimeoutThrowsInvalidRequest() async {
        let test = makeTestNetworkClient { request in
            (Data(), makeHTTPResponse(url: request.url!, statusCode: 200))
        }

        await assertNetworkError {
            _ = try await test.client.send(NetworkRequest(url: url, timeoutInterval: -1))
        } verify: { error in
            guard case .invalidRequest = error else {
                return XCTFail("Expected invalidRequest, got \(error)")
            }
        }
    }

    func testInvalidConfiguredTimeoutThrowsInvalidConfiguration() async {
        let test = makeTestNetworkClient(
            configuration: NetworkConfiguration(baseURL: baseURL, timeoutInterval: 0)
        ) { request in
            (Data(), makeHTTPResponse(url: request.url!, statusCode: 200))
        }

        await assertNetworkError {
            _ = try await test.client.send(NetworkRequest(url: url))
        } verify: { error in
            guard case .invalidConfiguration = error else {
                return XCTFail("Expected invalidConfiguration, got \(error)")
            }
        }
    }

    // MARK: - Response Headers and Status Handling

    func testResponseHeadersAreExposed() async throws {
        let headers = [
            "Content-Type": "application/json",
            "X-Request-ID": "request-123"
        ]
        let test = makeTestNetworkClient { request in
            (Data(), makeHTTPResponse(url: request.url!, statusCode: 200, headers: headers))
        }

        let response = try await test.client.send(NetworkRequest(url: url))

        XCTAssertEqual(response.header(named: "content-type"), "application/json")
        XCTAssertEqual(response.header(named: "x-request-id"), "request-123")
    }

    func testTwoHundredRangeStatusesAreAccepted() async throws {
        for statusCode in [200, 201, 204, 299] {
            let test = makeTestNetworkClient { request in
                (Data(), makeHTTPResponse(url: request.url!, statusCode: statusCode))
            }

            let response = try await test.client.send(NetworkRequest(url: url))
            XCTAssertEqual(response.statusCode, statusCode)
        }
    }

    func testStatusesOutsideTwoHundredRangeThrowHTTPStatus() async {
        for statusCode in [199, 300] {
            let test = makeTestNetworkClient { request in
                (Data(), makeHTTPResponse(url: request.url!, statusCode: statusCode))
            }

            await assertNetworkError {
                _ = try await test.client.send(NetworkRequest(url: url))
            } verify: { error in
                XCTAssertEqual(error.statusCode, statusCode)
            }
        }
    }

    func testCustomAcceptableStatusRangeIsRespected() async throws {
        let test = makeTestNetworkClient(
            configuration: NetworkConfiguration(baseURL: baseURL, acceptableStatusCodes: 200..<400)
        ) { request in
            (Data(), makeHTTPResponse(url: request.url!, statusCode: 302))
        }

        let response = try await test.client.send(NetworkRequest(url: url))

        XCTAssertEqual(response.statusCode, 302)
    }

    func testHTTPErrorPreservesResponseBodyAndHeaders() async {
        let errorBody = Data(#"{"error":"insufficient_funds"}"#.utf8)
        let test = makeTestNetworkClient { request in
            (
                errorBody,
                makeHTTPResponse(
                    url: request.url!,
                    statusCode: 422,
                    headers: ["Content-Type": "application/json", "X-Request-ID": "req-1"]
                )
            )
        }

        await assertNetworkError {
            _ = try await test.client.send(NetworkRequest(url: url))
        } verify: { error in
            guard case .httpStatus(let response) = error else {
                return XCTFail("Expected httpStatus, got \(error)")
            }
            XCTAssertEqual(response.statusCode, 422)
            XCTAssertEqual(response.data, errorBody)
            XCTAssertEqual(response.header(named: "x-request-id"), "req-1")
        }
    }

    // MARK: - Decoding

    func testDecodedSendDecodesJSON() async throws {
        let test = makeTestNetworkClient { request in
            (
                Data(#"{"identifier":"acc_1"}"#.utf8),
                makeHTTPResponse(url: request.url!, statusCode: 200)
            )
        }

        let account = try await test.client.send(
            NetworkRequest(url: url),
            as: AccountPayload.self
        )

        XCTAssertEqual(account, AccountPayload(identifier: "acc_1"))
    }

    func testDecodedSendUsesConfigurationDecoder() async throws {
        let configuration = NetworkConfiguration(
            baseURL: baseURL,
            decoderFactory: {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                return decoder
            }
        )
        let test = makeTestNetworkClient(configuration: configuration) { request in
            (
                Data(#"{"account_id":"acc_1"}"#.utf8),
                makeHTTPResponse(url: request.url!, statusCode: 200)
            )
        }

        let account = try await test.client.send(
            NetworkRequest(url: url),
            as: SnakeCaseAccount.self
        )

        XCTAssertEqual(account, SnakeCaseAccount(accountId: "acc_1"))
    }

    func testDecodedSendThrowsEmptyResponseForNoContent() async {
        let test = makeTestNetworkClient { request in
            (Data(), makeHTTPResponse(url: request.url!, statusCode: 204))
        }

        await assertNetworkError(.emptyResponse) {
            _ = try await test.client.send(NetworkRequest(url: url), as: AccountPayload.self)
        }
    }

    func testDecodedSendThrowsDecodingFailedForInvalidJSON() async {
        let test = makeTestNetworkClient { request in
            (Data("not-json".utf8), makeHTTPResponse(url: request.url!, statusCode: 200))
        }

        await assertNetworkError(.decodingFailed) {
            _ = try await test.client.send(NetworkRequest(url: url), as: AccountPayload.self)
        }
    }

    func testRawSendReturnsEmptyResponseForNoContent() async throws {
        let test = makeTestNetworkClient { request in
            (Data(), makeHTTPResponse(url: request.url!, statusCode: 204))
        }

        let response = try await test.client.send(NetworkRequest(url: url, method: .delete))

        XCTAssertEqual(response.statusCode, 204)
        XCTAssertTrue(response.data.isEmpty)
    }

    // MARK: - JSON Convenience

    func testSendJSONBodyEncodesAndSetsContentType() async throws {
        let test = makeTestNetworkClient { request in
            (Data(), makeHTTPResponse(url: request.url!, statusCode: 201))
        }

        let request = NetworkRequest(url: url, method: .post)
        _ = try await test.client.send(request, json: POSTBody(accountNumber: "12345678"))

        XCTAssertEqual(
            test.transport.lastRequest?.httpBody,
            Data(#"{"accountNumber":"12345678"}"#.utf8)
        )
        XCTAssertEqual(
            test.transport.lastRequest?.value(forHTTPHeaderField: "Content-Type"),
            "application/json"
        )
    }

    func testSendJSONBodyUsesConfigurationEncoder() async throws {
        let configuration = NetworkConfiguration(
            baseURL: baseURL,
            encoderFactory: {
                let encoder = JSONEncoder()
                encoder.keyEncodingStrategy = .convertToSnakeCase
                return encoder
            }
        )
        let test = makeTestNetworkClient(configuration: configuration) { request in
            (Data(), makeHTTPResponse(url: request.url!, statusCode: 201))
        }

        let request = NetworkRequest(url: url, method: .post)
        _ = try await test.client.send(request, json: POSTBody(accountNumber: "12345678"))

        XCTAssertEqual(
            test.transport.lastRequest?.httpBody,
            Data(#"{"account_number":"12345678"}"#.utf8)
        )
    }

    func testSendJSONBodyAndDecodeResponse() async throws {
        let test = makeTestNetworkClient { request in
            (
                Data(#"{"identifier":"acc_1"}"#.utf8),
                makeHTTPResponse(url: request.url!, statusCode: 201)
            )
        }

        let account = try await test.client.send(
            NetworkRequest(url: url, method: .post),
            json: POSTBody(accountNumber: "12345678"),
            as: AccountPayload.self
        )

        XCTAssertEqual(account, AccountPayload(identifier: "acc_1"))
    }

    func testSendJSONBodyThrowsEncodingFailed() async {
        let test = makeTestNetworkClient { request in
            (Data(), makeHTTPResponse(url: request.url!, statusCode: 200))
        }

        await assertNetworkError(.encodingFailed) {
            _ = try await test.client.send(
                NetworkRequest(url: url, method: .post),
                json: NonFiniteBody(value: .nan)
            )
        }

        XCTAssertTrue(test.transport.requests.isEmpty)
    }

    // MARK: - Invalid Response

    func testNonHTTPResponseThrowsInvalidResponse() async {
        let test = makeTestNetworkClient { request in
            (
                Data(),
                URLResponse(
                    url: request.url!,
                    mimeType: "application/json",
                    expectedContentLength: 0,
                    textEncodingName: nil
                )
            )
        }

        await assertNetworkError(.invalidResponse) {
            _ = try await test.client.send(NetworkRequest(url: url))
        }
    }

    // MARK: - Concurrency

    func testConcurrentRequestsCompleteIndependently() async throws {
        let gate = ConcurrencyGate()
        await gate.expect(2)
        let test = makeTestNetworkClient { request in
            await gate.arriveAndWait()
            let path = request.url?.path ?? ""
            return (Data(path.utf8), makeHTTPResponse(url: request.url!, statusCode: 200))
        }

        let firstURL = URL(string: "https://api.example.com/v1/first")!
        let secondURL = URL(string: "https://api.example.com/v1/second")!

        let firstTask = Task { try await test.client.send(NetworkRequest(url: firstURL)) }
        let secondTask = Task { try await test.client.send(NetworkRequest(url: secondURL)) }

        await gate.waitForArrivals()
        XCTAssertEqual(test.transport.requests.count, 2)

        await gate.open()
        let first = try await firstTask.value
        let second = try await secondTask.value

        XCTAssertEqual(String(data: first.data, encoding: .utf8), "/v1/first")
        XCTAssertEqual(String(data: second.data, encoding: .utf8), "/v1/second")
        XCTAssertEqual(test.transport.requests.count, 2)
    }

    func testConcurrentRequestsReceivePerRequestBearerTokens() async throws {
        let tokens = TokenSequence()
        let configuration = NetworkConfiguration(
            baseURL: baseURL,
            tokenProvider: { await tokens.next() }
        )
        let test = makeTestNetworkClient(configuration: configuration) { request in
            (Data("ok".utf8), makeHTTPResponse(url: request.url!, statusCode: 200))
        }

        let urls = (1...4).map { URL(string: "https://api.example.com/v1/items/\($0)")! }
        let statuses = try await withThrowingTaskGroup(of: Int.self) { group in
            for url in urls {
                group.addTask {
                    try await test.client.send(NetworkRequest(url: url)).statusCode
                }
            }

            var results: [Int] = []
            for try await status in group {
                results.append(status)
            }
            return results
        }

        XCTAssertEqual(test.transport.requests.count, 4)
        XCTAssertEqual(statuses.count, 4)

        let authorization = Set(
            test.transport.requests.compactMap { $0.value(forHTTPHeaderField: "Authorization") }
        )
        XCTAssertEqual(authorization.count, 4)
        XCTAssertTrue(authorization.allSatisfy { $0.hasPrefix("Bearer token_") })
        XCTAssertTrue(statuses.allSatisfy { $0 == 200 })
    }

    func testCancellingOneConcurrentRequestLeavesTheOtherRunning() async throws {
        let gate = ConcurrencyGate()
        await gate.expect(2)
        let test = makeTestNetworkClient { request in
            await gate.arriveAndWait()
            try Task.checkCancellation()
            return (Data("ok".utf8), makeHTTPResponse(url: request.url!, statusCode: 200))
        }

        let firstTask = Task {
            try await test.client.send(NetworkRequest(url: URL(string: "https://api.example.com/v1/cancelled")!))
        }
        let secondTask = Task {
            try await test.client.send(NetworkRequest(url: URL(string: "https://api.example.com/v1/completed")!))
        }

        await gate.waitForArrivals()
        firstTask.cancel()
        await gate.open()

        do {
            _ = try await firstTask.value
            XCTFail("Expected the cancelled request to throw.")
        } catch let error as NetworkError {
            XCTAssertEqual(error, .cancelled)
        }

        let second = try await secondTask.value
        XCTAssertEqual(second.statusCode, 200)
        XCTAssertEqual(String(data: second.data, encoding: .utf8), "ok")
    }

    // MARK: - Real URLSession Transport

    func testURLSessionTransportExecutesRequest() async throws {
        URLProtocolStub.handler.write { request in
            (
                makeHTTPResponse(url: request.url!, statusCode: 201),
                Data(#"{"identifier":"acc_1"}"#.utf8)
            )
        }
        defer { URLProtocolStub.handler.write(nil) }

        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: sessionConfiguration)
        let client = URLSessionNetworkClient(
            configuration: NetworkConfiguration(),
            logger: MockLogger(),
            transport: URLSessionTransport(session: session)
        )

        let response = try await client.send(NetworkRequest(url: url))

        XCTAssertEqual(response.statusCode, 201)
        XCTAssertEqual(response.data, Data(#"{"identifier":"acc_1"}"#.utf8))
    }

    func testSessionConfigurationFactoryInstallsCustomProtocolClasses() async throws {
        URLProtocolStub.handler.write { request in
            (
                makeHTTPResponse(url: request.url!, statusCode: 202),
                Data(#"{"source":"factory"}"#.utf8)
            )
        }
        defer { URLProtocolStub.handler.write(nil) }

        let configuration = NetworkConfiguration(
            baseURL: baseURL,
            sessionConfigurationFactory: {
                let sessionConfiguration = URLSessionConfiguration.ephemeral
                sessionConfiguration.protocolClasses = [URLProtocolStub.self]
                return sessionConfiguration
            }
        )
        let client = URLSessionNetworkClient(configuration: configuration, logger: MockLogger())

        let response = try await client.send(NetworkRequest(path: "/v1/accounts"))

        XCTAssertEqual(response.statusCode, 202)
        XCTAssertEqual(response.data, Data(#"{"source":"factory"}"#.utf8))
    }

    // MARK: - Helpers

    private func assertNetworkError(
        _ expected: NetworkError? = nil,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () async throws -> Void,
        verify: (NetworkError) -> Void = { _ in }
    ) async {
        do {
            try await operation()
            XCTFail("Expected a NetworkError to be thrown.", file: file, line: line)
        } catch let error as NetworkError {
            if let expected {
                XCTAssertEqual(error, expected, file: file, line: line)
            }
            verify(error)
        } catch {
            XCTFail("Expected a NetworkError, got \(error).", file: file, line: line)
        }
    }
}
