import Foundation
@testable import SwiftKit

/// Transport double that records prepared requests and returns scripted outcomes.
internal final class MockHTTPTransport: HTTPTransport, @unchecked Sendable {
    internal typealias Handler = (URLRequest) async throws -> (Data, URLResponse)

    private let handler: Handler
    private let recordedRequests = ThreadSafeBox<[URLRequest]>([])

    internal init(handler: @escaping Handler) {
        self.handler = handler
    }

    internal var requests: [URLRequest] {
        recordedRequests.current
    }

    internal var lastRequest: URLRequest? {
        requests.last
    }

    internal func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        recordedRequests.mutate { $0.append(request) }
        return try await handler(request)
    }
}

/// Convenience bundle for tests exercising ``URLSessionNetworkClient`` with a mock transport.
internal struct TestNetworkClient: Sendable {
    internal let client: URLSessionNetworkClient
    internal let transport: MockHTTPTransport
    internal let logger: MockLogger
}

/// Creates a networking client backed by a mock transport.
internal func makeTestNetworkClient(
    configuration: NetworkConfiguration = NetworkConfiguration(baseURL: URL(string: "https://api.example.com")!),
    logger: MockLogger = MockLogger(),
    handler: @escaping MockHTTPTransport.Handler
) -> TestNetworkClient {
    let transport = MockHTTPTransport(handler: handler)
    let client = URLSessionNetworkClient(
        configuration: configuration,
        logger: logger,
        transport: transport
    )
    return TestNetworkClient(client: client, transport: transport, logger: logger)
}

/// Builds an `HTTPURLResponse` for transport doubles.
internal func makeHTTPResponse(
    url: URL,
    statusCode: Int,
    headers: [String: String] = ["Content-Type": "application/json"]
) -> HTTPURLResponse {
    HTTPURLResponse(
        url: url,
        statusCode: statusCode,
        httpVersion: "HTTP/1.1",
        headerFields: headers
    )!
}

/// `URLProtocol` stub used to exercise the real `URLSessionTransport` without network access.
internal final class URLProtocolStub: URLProtocol {
    internal typealias Handler = (URLRequest) -> (HTTPURLResponse, Data)

    internal static let handler = ThreadSafeBox<Handler?>(nil)

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler.current else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }

        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
