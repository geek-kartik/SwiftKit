import XCTest
@testable import SwiftKit

private struct ItemResponse: Decodable, Equatable, Sendable {
    let id: String
}

final class NetworkClientConcurrencyTests: XCTestCase {
    func testConcurrentDecodedRequestsCompleteIndependently() async {
        let test = makeTestNetworkClient { request in
            let id = request.url?.lastPathComponent ?? "unknown"
            return (
                Data(#"{"id":"\#(id)"}"#.utf8),
                makeHTTPResponse(url: request.url!, statusCode: 200)
            )
        }

        let results = ThreadSafeBox<[Int: String]>([:])

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<50 {
                group.addTask {
                    do {
                        let request = try NetworkRequest(path: "/items/\(index)")
                        let item = try await test.client.send(
                            request,
                            as: ItemResponse.self
                        )
                        results.mutate { $0[index] = item.id }
                    } catch {
                        results.mutate { $0[index] = "error: \(error)" }
                    }
                }
            }
        }

        XCTAssertEqual(results.current.count, 50)
        for index in 0..<50 {
            XCTAssertEqual(results.current[index], "\(index)")
        }
    }

    func testConcurrentRequestsKeepHeadersIsolated() async {
        let test = makeTestNetworkClient { request in
            (Data(), makeHTTPResponse(url: request.url!, statusCode: 200))
        }

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<50 {
                group.addTask {
                    guard let request = try? NetworkRequest(
                        path: "/items/\(index)",
                        headers: ["X-Request-ID": "\(index)"]
                    ) else {
                        return
                    }
                    _ = try? await test.client.send(request)
                }
            }
        }

        XCTAssertEqual(test.transport.requests.count, 50)

        for request in test.transport.requests {
            let expectedID = request.url?.lastPathComponent
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Request-ID"), expectedID)
        }
    }

    func testConcurrentRequestsHandleMixedSuccessAndFailure() async {
        let test = makeTestNetworkClient { request in
            let id = Int(request.url?.lastPathComponent ?? "") ?? 0
            let statusCode = id.isMultiple(of: 2) ? 200 : 500
            return (Data(), makeHTTPResponse(url: request.url!, statusCode: statusCode))
        }

        let successes = ThreadSafeBox<Int>(0)
        let failures = ThreadSafeBox<Int>(0)

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<40 {
                group.addTask {
                    do {
                        let request = try NetworkRequest(path: "/items/\(index)")
                        _ = try await test.client.send(request)
                        successes.mutate { $0 += 1 }
                    } catch {
                        failures.mutate { $0 += 1 }
                    }
                }
            }
        }

        XCTAssertEqual(successes.current, 20)
        XCTAssertEqual(failures.current, 20)
    }
}
