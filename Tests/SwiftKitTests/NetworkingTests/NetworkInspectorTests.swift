import XCTest
@testable import SwiftKit

/// Tests for structured transaction capture and the session inspector store.
final class NetworkInspectorTests: XCTestCase {
    private let baseURL = URL(string: "https://api.example.com")!

    // MARK: - Store

    func testRecordStoresNewestFirst() {
        let inspector = makeInspector()
        let older = makeTransaction(method: .get, path: "/older")
        let newer = makeTransaction(method: .post, path: "/newer")

        inspector.record(older)
        inspector.record(newer)

        XCTAssertEqual(inspector.transactions.map(\.id), [newer.id, older.id])
    }

    func testRetentionDropsOldestTransactions() {
        let inspector = NetworkInspector(
            configuration: NetworkInspectorConfiguration(isEnabled: true, maxTransactions: 3)
        )

        for index in 0..<5 {
            inspector.record(makeTransaction(method: .get, path: "/item-\(index)"))
        }

        XCTAssertEqual(inspector.transactions.count, 3)
        XCTAssertEqual(inspector.transactions.map(\.pathText), ["/item-4", "/item-3", "/item-2"])
    }

    func testDisabledInspectorDropsTransactions() {
        let inspector = NetworkInspector(configuration: .disabled)

        inspector.record(makeTransaction(method: .get, path: "/ignored"))

        XCTAssertTrue(inspector.transactions.isEmpty)
    }

    func testClearRemovesHistory() {
        let inspector = makeInspector()
        inspector.record(makeTransaction(method: .get, path: "/one"))

        inspector.clear()

        XCTAssertTrue(inspector.transactions.isEmpty)
        XCTAssertNil(inspector.transaction(id: UUID()))
    }

    func testTransactionLookupByIdentifier() {
        let inspector = makeInspector()
        let transaction = makeTransaction(method: .patch, path: "/v1/accounts/acc-1")
        inspector.record(transaction)

        XCTAssertEqual(inspector.transaction(id: transaction.id), transaction)
    }

    func testBodiesAreTruncatedToCaptureLimit() {
        let inspector = NetworkInspector(
            configuration: NetworkInspectorConfiguration(
                isEnabled: true,
                maxBodyBytes: 8
            )
        )

        let body = NetworkTransaction.Body(data: Data("0123456789".utf8))
        let transaction = makeTransaction(method: .post, path: "/v1/transfers", body: body)
        inspector.record(transaction)

        let stored = try? XCTUnwrap(inspector.transactions.first?.request.body)
        XCTAssertEqual(stored?.data, Data("01234567".utf8))
        XCTAssertEqual(stored?.totalByteCount, 10)
        XCTAssertTrue(stored?.isTruncated == true)
    }

    func testUpdatesDeliversSnapshotThenChanges() async {
        let inspector = makeInspector()
        var iterator = inspector.updates().makeAsyncIterator()

        let initial = await iterator.next()
        XCTAssertEqual(initial?.count, 0)

        let transaction = makeTransaction(method: .get, path: "/v1/accounts")
        inspector.record(transaction)

        let updated = await iterator.next()
        XCTAssertEqual(updated?.map(\.id), [transaction.id])

        inspector.clear()

        let cleared = await iterator.next()
        XCTAssertEqual(cleared?.count, 0)
    }

    // MARK: - Client capture

    func testClientRecordsSuccessfulTransaction() async throws {
        let inspector = makeInspector()
        let configuration = NetworkConfiguration(
            baseURL: baseURL,
            defaultHeaders: ["Accept": "application/json"],
            inspector: .init(isEnabled: true)
        )
        let responseBody = Data(#"{"ok":true}"#.utf8)

        let test = makeTestNetworkClient(
            configuration: configuration,
            inspector: inspector,
            handler: { request in
                (responseBody, makeHTTPResponse(url: request.url!, statusCode: 200))
            }
        )

        let request = try NetworkRequest(
            path: "/v1/accounts",
            method: .post,
            headers: ["Authorization": "Bearer token", "Content-Type": "application/json"],
            queryItems: [URLQueryItem(name: "limit", value: "1")],
            body: Data(#"{"query":"all"}"#.utf8)
        )

        _ = try await test.client.send(request)

        let transaction = try XCTUnwrap(inspector.transactions.first)
        XCTAssertEqual(transaction.request.method, .post)
        XCTAssertEqual(
            transaction.request.url.absoluteString,
            "https://api.example.com/v1/accounts?limit=1"
        )
        XCTAssertEqual(transaction.request.headers["Accept"], "application/json")
        XCTAssertEqual(transaction.request.headers["Authorization"], "Bearer token")
        XCTAssertEqual(transaction.request.body?.text, #"{"query":"all"}"#)
        XCTAssertEqual(transaction.response?.statusCode, 200)
        XCTAssertEqual(transaction.response?.body.data, responseBody)
        XCTAssertNil(transaction.error)
        XCTAssertTrue(transaction.isSuccess)
        XCTAssertGreaterThanOrEqual(transaction.duration, 0)
    }

    func testClientRecordsRejectedStatusWithResponse() async throws {
        let inspector = makeInspector()
        let configuration = NetworkConfiguration(
            baseURL: baseURL,
            inspector: .init(isEnabled: true)
        )
        let errorBody = Data(#"{"error":"nope"}"#.utf8)

        let test = makeTestNetworkClient(
            configuration: configuration,
            inspector: inspector,
            handler: { request in
                (errorBody, makeHTTPResponse(url: request.url!, statusCode: 422))
            }
        )

        do {
            _ = try await test.client.send(try NetworkRequest(path: "/v1/transfers", method: .post))
            XCTFail("Expected the request to fail")
        } catch {
            XCTAssertEqual((error as? NetworkError)?.statusCode, 422)
        }

        let transaction = try XCTUnwrap(inspector.transactions.first)
        XCTAssertEqual(transaction.statusCode, 422)
        XCTAssertEqual(transaction.response?.body.data, errorBody)
        XCTAssertEqual(transaction.error?.statusCode, 422)
        XCTAssertFalse(transaction.isSuccess)
    }

    func testClientRecordsTransportFailure() async throws {
        let inspector = makeInspector()
        let configuration = NetworkConfiguration(
            baseURL: baseURL,
            inspector: .init(isEnabled: true)
        )

        let test = makeTestNetworkClient(
            configuration: configuration,
            inspector: inspector,
            handler: { _ in throw URLError(.timedOut) }
        )

        _ = try? await test.client.send(try NetworkRequest(path: "/v1/accounts"))

        let transaction = try XCTUnwrap(inspector.transactions.first)
        XCTAssertEqual(transaction.error, .timeout)
        XCTAssertNil(transaction.response)
        XCTAssertTrue(transaction.isRetryable)
    }

    func testClientRecordsCancellation() async throws {
        let inspector = makeInspector()
        let configuration = NetworkConfiguration(
            baseURL: baseURL,
            inspector: .init(isEnabled: true)
        )

        let test = makeTestNetworkClient(
            configuration: configuration,
            inspector: inspector,
            handler: { _ in throw CancellationError() }
        )

        _ = try? await test.client.send(try NetworkRequest(path: "/v1/accounts"))

        XCTAssertEqual(inspector.transactions.first?.error, .cancelled)
    }

    func testClientRecordsInvalidResponse() async throws {
        let inspector = makeInspector()
        let configuration = NetworkConfiguration(
            baseURL: baseURL,
            inspector: .init(isEnabled: true)
        )

        let test = makeTestNetworkClient(
            configuration: configuration,
            inspector: inspector,
            handler: { request in
                let response = URLResponse(
                    url: request.url!,
                    mimeType: nil,
                    expectedContentLength: 0,
                    textEncodingName: nil
                )
                return (Data(), response)
            }
        )

        _ = try? await test.client.send(try NetworkRequest(path: "/v1/accounts"))

        XCTAssertEqual(inspector.transactions.first?.error, .invalidResponse)
    }

    func testClientRecordsInvalidURLBeforeTransport() async throws {
        let inspector = makeInspector()
        let configuration = NetworkConfiguration(inspector: .init(isEnabled: true))
        let test = makeTestNetworkClient(
            configuration: configuration,
            inspector: inspector,
            handler: { request in
                (Data(), makeHTTPResponse(url: request.url!, statusCode: 200))
            }
        )

        _ = try? await test.client.send(try NetworkRequest(path: "/relative"))

        let transaction = try XCTUnwrap(inspector.transactions.first)
        XCTAssertEqual(transaction.error, .invalidURL)
        XCTAssertTrue(transaction.request.url.absoluteString.hasSuffix("/relative"))
        XCTAssertTrue(test.transport.requests.isEmpty)
    }

    func testDisabledInspectorRecordsNothingFromClient() async throws {
        let inspector = NetworkInspector(configuration: .disabled)
        let test = makeTestNetworkClient(
            configuration: NetworkConfiguration(baseURL: baseURL),
            inspector: inspector,
            handler: { request in
                (Data("{}".utf8), makeHTTPResponse(url: request.url!, statusCode: 200))
            }
        )

        _ = try await test.client.send(try NetworkRequest(path: "/v1/accounts"))

        XCTAssertTrue(inspector.transactions.isEmpty)
    }

    // MARK: - Configuration

    func testInspectorIsDisabledByDefault() {
        XCTAssertFalse(NetworkConfiguration().inspector.isEnabled)
    }

    func testInvalidRetentionIsRejected() {
        let configuration = NetworkConfiguration(
            inspector: .init(isEnabled: true, maxTransactions: 0)
        )

        XCTAssertThrowsError(try configuration.validate())
    }

    func testInvalidBodyLimitIsRejected() {
        let configuration = NetworkConfiguration(
            inspector: .init(isEnabled: true, maxBodyBytes: -1)
        )

        XCTAssertThrowsError(try configuration.validate())
    }

    // MARK: - Helpers

    private func makeInspector() -> NetworkInspector {
        NetworkInspector(configuration: NetworkInspectorConfiguration(isEnabled: true))
    }

    private func makeTransaction(
        method: HTTPMethod,
        path: String,
        body: NetworkTransaction.Body? = nil
    ) -> NetworkTransaction {
        let url = URL(string: "https://api.example.com\(path)")!
        return NetworkTransaction(
            startedAt: Date(),
            duration: 0.042,
            request: NetworkTransaction.Request(method: method, url: url, body: body),
            response: NetworkTransaction.Response(statusCode: 200, body: .init(data: Data())),
            error: nil
        )
    }
}
