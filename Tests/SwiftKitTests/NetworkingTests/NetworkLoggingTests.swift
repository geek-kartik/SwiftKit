import XCTest
@testable import SwiftKit

/// Tests for the console diagnostics emitted by ``URLSessionNetworkClient``.
final class NetworkLoggingTests: XCTestCase {
    private let baseURL = URL(string: "https://api.example.com")!

    // MARK: - Verbose blocks

    func testVerboseLogsRequestAndResponseBlock() async throws {
        let responseBody = Data(#"{"accounts":[{"id":"acc-1001"}],"status":"ok"}"#.utf8)
        let test = makeTestNetworkClient(
            configuration: NetworkConfiguration(baseURL: baseURL, logVerbosity: .verbose),
            handler: { request in
                (responseBody, makeHTTPResponse(url: request.url!, statusCode: 200))
            }
        )

        let request = try NetworkRequest(
            path: "/v1/accounts",
            method: .post,
            headers: ["Content-Type": "application/json"],
            body: Data(#"{"query":"all"}"#.utf8)
        )

        _ = try await test.client.send(request)

        XCTAssertEqual(test.logger.recordedEntries.count, 1)
        let entry = try XCTUnwrap(test.logger.recordedEntries.first)
        XCTAssertEqual(entry.level, .info)
        XCTAssertTrue(entry.message.hasPrefix("[HTTP] ┌─ POST https://api.example.com/v1/accounts"))
        XCTAssertTrue(entry.message.contains("[HTTP] │ Request headers"))
        XCTAssertTrue(entry.message.contains("Content-Type: application/json"))
        XCTAssertTrue(entry.message.contains("[HTTP] │ Request body · 15 B"))
        XCTAssertTrue(entry.message.contains("\"query\": \"all\""))
        XCTAssertTrue(entry.message.contains("← 200 OK"))
        XCTAssertTrue(entry.message.contains("[HTTP] │ Response headers"))
        XCTAssertTrue(entry.message.contains("[HTTP] │ Response body"))
        XCTAssertTrue(entry.message.contains("\"accounts\": ["))
        XCTAssertTrue(entry.message.contains("[HTTP] └─"))
    }

    func testVerboseMergesDefaultHeadersIntoBlock() async throws {
        let test = makeTestNetworkClient(
            configuration: NetworkConfiguration(
                baseURL: baseURL,
                defaultHeaders: ["Accept": "application/json"],
                logVerbosity: .verbose
            ),
            handler: { request in
                (Data("{}".utf8), makeHTTPResponse(url: request.url!, statusCode: 200))
            }
        )

        _ = try await test.client.send(try NetworkRequest(path: "/health"))

        let message = try XCTUnwrap(test.logger.recordedEntries.first?.message)
        XCTAssertTrue(message.contains("Accept: application/json"))
    }

    func testVerboseRedactsCredentialHeaders() async throws {
        let test = makeTestNetworkClient(
            configuration: NetworkConfiguration(baseURL: baseURL, logVerbosity: .verbose),
            handler: { request in
                (Data("{}".utf8), makeHTTPResponse(url: request.url!, statusCode: 200))
            }
        )

        let request = try NetworkRequest(
            path: "/v1/accounts",
            headers: [
                "Authorization": "Bearer super-secret-token",
                "Cookie": "session=abc123",
                "X-Api-Key": "key-123"
            ]
        )

        _ = try await test.client.send(request)

        let message = try XCTUnwrap(test.logger.recordedEntries.first?.message)
        XCTAssertTrue(message.contains("Authorization: [REDACTED]"))
        XCTAssertTrue(message.contains("Cookie: [REDACTED]"))
        XCTAssertTrue(message.contains("X-Api-Key: [REDACTED]"))
        XCTAssertFalse(message.contains("super-secret-token"))
        XCTAssertFalse(message.contains("session=abc123"))
        XCTAssertFalse(message.contains("key-123"))
    }

    func testVerboseMasksEmailsInResponseBody() async throws {
        let body = Data(#"{"customer":{"email":"alice@example.com"}}"#.utf8)
        let test = makeTestNetworkClient(
            configuration: NetworkConfiguration(baseURL: baseURL, logVerbosity: .verbose),
            handler: { request in
                (body, makeHTTPResponse(url: request.url!, statusCode: 200))
            }
        )

        _ = try await test.client.send(try NetworkRequest(path: "/v1/customer"))

        let message = try XCTUnwrap(test.logger.recordedEntries.first?.message)
        XCTAssertTrue(message.contains("a***e@example.com"))
        XCTAssertFalse(message.contains("alice@example.com"))
    }

    func testVerboseTruncatesLargeBodies() async throws {
        let longBody = Data(String(repeating: "a", count: 500).utf8)
        let test = makeTestNetworkClient(
            configuration: NetworkConfiguration(
                baseURL: baseURL,
                logVerbosity: .verbose,
                maxLoggedBodyBytes: 100
            ),
            handler: { request in
                (longBody, makeHTTPResponse(url: request.url!, statusCode: 200))
            }
        )

        _ = try await test.client.send(try NetworkRequest(path: "/large"))

        let message = try XCTUnwrap(test.logger.recordedEntries.first?.message)
        XCTAssertTrue(message.contains("Response body · 500 B · showing first 100 bytes"))
        XCTAssertTrue(message.contains("aaa"))
        XCTAssertFalse(message.contains(String(repeating: "a", count: 101)))
    }

    func testVerboseOmitsBodyContentWhenLimitIsZero() async throws {
        let test = makeTestNetworkClient(
            configuration: NetworkConfiguration(
                baseURL: baseURL,
                logVerbosity: .verbose,
                maxLoggedBodyBytes: 0
            ),
            handler: { request in
                (Data(#"{"ok":true}"#.utf8), makeHTTPResponse(url: request.url!, statusCode: 200))
            }
        )

        _ = try await test.client.send(try NetworkRequest(path: "/health"))

        let message = try XCTUnwrap(test.logger.recordedEntries.first?.message)
        XCTAssertTrue(message.contains("Response body · 11 B"))
        XCTAssertFalse(message.contains("\"ok\""))
        XCTAssertFalse(message.contains("binary"))
    }

    func testVerboseDescribesBinaryBodies() async throws {
        let test = makeTestNetworkClient(
            configuration: NetworkConfiguration(baseURL: baseURL, logVerbosity: .verbose),
            handler: { request in
                (Data([0xFF, 0xFE, 0x00, 0x01]), makeHTTPResponse(url: request.url!, statusCode: 200))
            }
        )

        _ = try await test.client.send(try NetworkRequest(path: "/image"))

        let message = try XCTUnwrap(test.logger.recordedEntries.first?.message)
        XCTAssertTrue(message.contains("<binary 4 bytes>"))
    }

    func testVerbosePrettyPrintsWithoutReencodingNumbers() async throws {
        let body = Data(#"{"balance":58210.4,"precise":1.234567890123456789}"#.utf8)
        let test = makeTestNetworkClient(
            configuration: NetworkConfiguration(baseURL: baseURL, logVerbosity: .verbose),
            handler: { request in
                (body, makeHTTPResponse(url: request.url!, statusCode: 200))
            }
        )

        _ = try await test.client.send(try NetworkRequest(path: "/v1/accounts"))

        let message = try XCTUnwrap(test.logger.recordedEntries.first?.message)
        XCTAssertTrue(message.contains("\"balance\": 58210.4"))
        XCTAssertFalse(message.contains("58210.400000000001"))
        XCTAssertTrue(message.contains("\"precise\": 1.234567890123456789"))
    }

    func testVerbosePreservesEscapesAndEmptyContainers() async throws {
        let body = Data(#"{"note":"say \"hi\"","tags":[],"meta":{}}"#.utf8)
        let test = makeTestNetworkClient(
            configuration: NetworkConfiguration(baseURL: baseURL, logVerbosity: .verbose),
            handler: { request in
                (body, makeHTTPResponse(url: request.url!, statusCode: 200))
            }
        )

        _ = try await test.client.send(try NetworkRequest(path: "/v1/notes"))

        let message = try XCTUnwrap(test.logger.recordedEntries.first?.message)
        XCTAssertTrue(message.contains(#""note": "say \"hi\"""#))
        XCTAssertTrue(message.contains("\"tags\": []"))
        XCTAssertTrue(message.contains("\"meta\": {}"))
    }

    func testVerboseFallsBackToRawTextForIncompleteJSON() async throws {
        let body = Data(#"{"accounts":[{"id":"acc-1001""#.utf8)
        let test = makeTestNetworkClient(
            configuration: NetworkConfiguration(baseURL: baseURL, logVerbosity: .verbose),
            handler: { request in
                (body, makeHTTPResponse(url: request.url!, statusCode: 200))
            }
        )

        _ = try await test.client.send(try NetworkRequest(path: "/v1/accounts"))

        let message = try XCTUnwrap(test.logger.recordedEntries.first?.message)
        XCTAssertTrue(message.contains(#"{"accounts":[{"id":"acc-1001""#))
    }

    func testVerboseLogsNoBodyForNoContentResponses() async throws {
        let test = makeTestNetworkClient(
            configuration: NetworkConfiguration(baseURL: baseURL, logVerbosity: .verbose),
            handler: { request in
                (Data(), makeHTTPResponse(url: request.url!, statusCode: 204))
            }
        )

        _ = try await test.client.send(
            try NetworkRequest(path: "/v1/accounts/acc-1001/alerts", method: .delete)
        )

        let message = try XCTUnwrap(test.logger.recordedEntries.first?.message)
        XCTAssertTrue(message.contains("204 No Content"))
        XCTAssertFalse(message.contains("Response body"))
    }

    func testVerboseChunksLargeBlocksBelowOSLogLimit() async throws {
        let items = (0..<80)
            .map { #"{"id":"item-\#($0)","note":"\#(String(repeating: "x", count: 20))"}"# }
            .joined(separator: ",")
        let body = Data("{\"items\":[\(items)]}".utf8)

        let test = makeTestNetworkClient(
            configuration: NetworkConfiguration(baseURL: baseURL, logVerbosity: .verbose),
            handler: { request in
                (body, makeHTTPResponse(url: request.url!, statusCode: 200))
            }
        )

        _ = try await test.client.send(try NetworkRequest(path: "/v1/items"))

        let entries = test.logger.recordedEntries
        XCTAssertGreaterThan(entries.count, 1, "Large blocks must be split around os_log's 1 KB limit")
        XCTAssertTrue(entries.allSatisfy { $0.message.utf8.count <= 800 })
        XCTAssertTrue(entries.allSatisfy { $0.level == .info })

        let joined = entries.map(\.message).joined(separator: "\n")
        XCTAssertTrue(joined.contains("\"id\": \"item-79\""))
        XCTAssertTrue(joined.contains("[HTTP] └─"))
    }

    // MARK: - Failures

    func testVerboseLogsTransportFailureAsErrorBlock() async throws {
        let test = makeTestNetworkClient(
            configuration: NetworkConfiguration(baseURL: baseURL, logVerbosity: .verbose),
            handler: { _ in
                throw URLError(.timedOut)
            }
        )

        do {
            _ = try await test.client.send(try NetworkRequest(path: "/v1/accounts"))
            XCTFail("Expected the request to fail")
        } catch {
            XCTAssertEqual(error as? NetworkError, .timeout)
        }

        let entry = try XCTUnwrap(test.logger.recordedEntries.first)
        XCTAssertEqual(entry.level, .error)
        XCTAssertTrue(entry.message.contains("GET https://api.example.com/v1/accounts"))
        XCTAssertTrue(entry.message.contains("✖ Failed · timeout"))
        XCTAssertTrue(entry.message.contains("The network request timed out."))
    }

    func testVerboseLogsUnacceptedStatusAsWarningBlock() async throws {
        let errorBody = Data(#"{"error":{"code":"insufficient_funds"}}"#.utf8)
        let test = makeTestNetworkClient(
            configuration: NetworkConfiguration(baseURL: baseURL, logVerbosity: .verbose),
            handler: { request in
                (errorBody, makeHTTPResponse(url: request.url!, statusCode: 500))
            }
        )

        do {
            _ = try await test.client.send(try NetworkRequest(path: "/v1/transfers", method: .post))
            XCTFail("Expected the request to fail")
        } catch {
            XCTAssertEqual((error as? NetworkError)?.statusCode, 500)
        }

        let entry = try XCTUnwrap(test.logger.recordedEntries.first)
        XCTAssertEqual(entry.level, .warning)
        XCTAssertTrue(entry.message.contains("✖ 500 Internal Server Error"))
        XCTAssertTrue(entry.message.contains("insufficient_funds"))
    }

    // MARK: - Verbosity modes

    func testOffSuppressesSuccessfulAndFailedRequests() async throws {
        let successTest = makeTestNetworkClient(
            configuration: NetworkConfiguration(baseURL: baseURL, logVerbosity: .off),
            handler: { request in
                (Data("{}".utf8), makeHTTPResponse(url: request.url!, statusCode: 200))
            }
        )

        _ = try await successTest.client.send(try NetworkRequest(path: "/health"))
        XCTAssertTrue(successTest.logger.recordedEntries.isEmpty)

        let failureTest = makeTestNetworkClient(
            configuration: NetworkConfiguration(baseURL: baseURL, logVerbosity: .off),
            handler: { request in
                (Data("{}".utf8), makeHTTPResponse(url: request.url!, statusCode: 500))
            }
        )

        _ = try? await failureTest.client.send(try NetworkRequest(path: "/health"))
        XCTAssertTrue(failureTest.logger.recordedEntries.isEmpty)
    }

    func testSummaryKeepsSingleLineOutput() async throws {
        let test = makeTestNetworkClient(
            configuration: NetworkConfiguration(baseURL: baseURL, logVerbosity: .summary),
            handler: { request in
                (Data("{}".utf8), makeHTTPResponse(url: request.url!, statusCode: 200))
            }
        )

        _ = try await test.client.send(try NetworkRequest(path: "/v1/accounts"))

        XCTAssertEqual(test.logger.recordedEntries.count, 1)
        let message = try XCTUnwrap(test.logger.recordedEntries.first?.message)
        XCTAssertTrue(message.hasPrefix("GET api.example.com -> 200 in "))
        XCTAssertFalse(message.contains("[HTTP]"))
        XCTAssertFalse(message.contains("\n"))
    }

    // MARK: - Configuration

    func testNegativeBodyLimitIsRejected() {
        let configuration = NetworkConfiguration(maxLoggedBodyBytes: -1)
        XCTAssertThrowsError(try configuration.validate())
    }

    func testZeroBodyLimitIsValid() {
        XCTAssertNoThrow(try NetworkConfiguration(maxLoggedBodyBytes: 0).validate())
    }
}
