import XCTest
@testable import SwiftKit

/// Tests for the global error and authentication-failure callbacks.
final class NetworkCallbackTests: XCTestCase {
    private let baseURL = URL(string: "https://api.example.com")!

    // MARK: - onError

    func testOnErrorReceivesRejectedStatus() async throws {
        let recorder = TransactionRecorder()
        let test = makeTestNetworkClient(
            configuration: makeConfiguration(onError: { recorder.append($0) }),
            handler: { request in
                (Data(#"{"error":"nope"}"#.utf8), makeHTTPResponse(url: request.url!, statusCode: 500))
            }
        )

        _ = try? await test.client.send(try NetworkRequest(path: "/v1/transfers", method: .post))

        let transaction = try XCTUnwrap(recorder.transactions.first)
        XCTAssertEqual(transaction.statusCode, 500)
        XCTAssertEqual(transaction.error?.statusCode, 500)
        XCTAssertEqual(transaction.response?.body.text, #"{"error":"nope"}"#)
    }

    func testOnErrorReceivesTransportFailure() async throws {
        let recorder = TransactionRecorder()
        let test = makeTestNetworkClient(
            configuration: makeConfiguration(onError: { recorder.append($0) }),
            handler: { _ in throw URLError(.timedOut) }
        )

        _ = try? await test.client.send(try NetworkRequest(path: "/v1/accounts"))

        XCTAssertEqual(recorder.transactions.first?.error, .timeout)
    }

    func testOnErrorIsNotCalledForSuccess() async throws {
        let recorder = TransactionRecorder()
        let test = makeTestNetworkClient(
            configuration: makeConfiguration(onError: { recorder.append($0) }),
            handler: { request in
                (Data("{}".utf8), makeHTTPResponse(url: request.url!, statusCode: 200))
            }
        )

        _ = try await test.client.send(try NetworkRequest(path: "/health"))

        XCTAssertTrue(recorder.transactions.isEmpty)
    }

    func testOnErrorRunsBeforeTheErrorIsThrown() async throws {
        let order = ThreadSafeBox<[String]>([])
        let test = makeTestNetworkClient(
            configuration: makeConfiguration(onError: { _ in
                order.mutate { $0.append("handler") }
            }),
            handler: { request in
                (Data(), makeHTTPResponse(url: request.url!, statusCode: 500))
            }
        )

        do {
            _ = try await test.client.send(try NetworkRequest(path: "/v1/accounts"))
            XCTFail("Expected the request to fail")
        } catch {
            order.mutate { $0.append("thrown") }
        }

        XCTAssertEqual(order.current, ["handler", "thrown"])
    }

    // MARK: - Authentication

    func testAuthenticationCallbackReceives401() async throws {
        let recorder = TransactionRecorder()
        let test = makeTestNetworkClient(
            configuration: makeConfiguration(onAuthenticationFailure: { recorder.append($0) }),
            handler: { request in
                (Data(#"{"error":"unauthorized"}"#.utf8), makeHTTPResponse(url: request.url!, statusCode: 401))
            }
        )

        _ = try? await test.client.send(try NetworkRequest(path: "/v1/accounts"))

        let transaction = try XCTUnwrap(recorder.transactions.first)
        XCTAssertEqual(transaction.statusCode, 401)
        XCTAssertTrue(transaction.isAuthenticationFailure)
    }

    func testAuthenticationCallbackReceives403() async throws {
        let recorder = TransactionRecorder()
        let test = makeTestNetworkClient(
            configuration: makeConfiguration(onAuthenticationFailure: { recorder.append($0) }),
            handler: { request in
                (Data(), makeHTTPResponse(url: request.url!, statusCode: 403))
            }
        )

        _ = try? await test.client.send(try NetworkRequest(path: "/v1/accounts"))

        XCTAssertEqual(recorder.transactions.first?.statusCode, 403)
    }

    func testAuthenticationCallbackIgnoresOtherFailures() async throws {
        let recorder = TransactionRecorder()
        let test = makeTestNetworkClient(
            configuration: makeConfiguration(onAuthenticationFailure: { recorder.append($0) }),
            handler: { request in
                (Data(), makeHTTPResponse(url: request.url!, statusCode: 422))
            }
        )

        _ = try? await test.client.send(try NetworkRequest(path: "/v1/transfers", method: .post))

        XCTAssertTrue(recorder.transactions.isEmpty)
    }

    func testAuthenticationCallbackIgnoresSuccess() async throws {
        let recorder = TransactionRecorder()
        let test = makeTestNetworkClient(
            configuration: makeConfiguration(onAuthenticationFailure: { recorder.append($0) }),
            handler: { request in
                (Data("{}".utf8), makeHTTPResponse(url: request.url!, statusCode: 200))
            }
        )

        _ = try await test.client.send(try NetworkRequest(path: "/health"))

        XCTAssertTrue(recorder.transactions.isEmpty)
    }

    func testBothCallbacksRunForAuthenticationFailure() async throws {
        let general = TransactionRecorder()
        let authentication = TransactionRecorder()
        let test = makeTestNetworkClient(
            configuration: makeConfiguration(
                onError: { general.append($0) },
                onAuthenticationFailure: { authentication.append($0) }
            ),
            handler: { request in
                (Data(), makeHTTPResponse(url: request.url!, statusCode: 401))
            }
        )

        _ = try? await test.client.send(try NetworkRequest(path: "/v1/accounts"))

        XCTAssertEqual(general.transactions.map(\.statusCode), [401])
        XCTAssertEqual(authentication.transactions.map(\.statusCode), [401])
    }

    // MARK: - Decoding

    func testDecodingFailureNotifiesOnError() async {
        struct Payload: Decodable {
            let expected: String
        }

        let recorder = TransactionRecorder()
        let test = makeTestNetworkClient(
            configuration: makeConfiguration(onError: { recorder.append($0) }),
            handler: { request in
                (Data(#"{"unexpected":true}"#.utf8), makeHTTPResponse(url: request.url!, statusCode: 200))
            }
        )

        do {
            _ = try await test.client.send(try NetworkRequest(path: "/v1/accounts"), as: Payload.self)
            XCTFail("Expected decoding to fail")
        } catch {
            XCTAssertEqual(error as? NetworkError, .decodingFailed)
        }

        let transaction = try? XCTUnwrap(recorder.transactions.first)
        XCTAssertEqual(transaction?.error, .decodingFailed)
        XCTAssertEqual(transaction?.request.url.absoluteString, "https://api.example.com/v1/accounts")
        XCTAssertEqual(transaction?.response?.statusCode, 200)
    }

    func testDecodingFailureNotifiesOnlyOnce() async {
        struct Payload: Decodable {
            let expected: String
        }

        let recorder = TransactionRecorder()
        let test = makeTestNetworkClient(
            configuration: makeConfiguration(onError: { recorder.append($0) }),
            handler: { request in
                (Data("not json".utf8), makeHTTPResponse(url: request.url!, statusCode: 200))
            }
        )

        _ = try? await test.client.send(try NetworkRequest(path: "/v1/accounts"), as: Payload.self)

        XCTAssertEqual(recorder.transactions.count, 1)
        XCTAssertEqual(recorder.transactions.first?.error, .decodingFailed)
    }

    // MARK: - Helpers

    private func makeConfiguration(
        onError: NetworkConfiguration.TransactionHandler? = nil,
        onAuthenticationFailure: NetworkConfiguration.TransactionHandler? = nil
    ) -> NetworkConfiguration {
        NetworkConfiguration(
            baseURL: baseURL,
            onError: onError,
            onAuthenticationFailure: onAuthenticationFailure
        )
    }
}

/// Thread-safe recorder for callback payloads.
private final class TransactionRecorder: @unchecked Sendable {
    private let storage = ThreadSafeBox<[NetworkTransaction]>([])

    var transactions: [NetworkTransaction] {
        storage.current
    }

    func append(_ transaction: NetworkTransaction) {
        storage.mutate { $0.append(transaction) }
    }
}
