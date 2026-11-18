import Foundation

/// Internal abstraction over `URLSession` to keep request construction and status handling
/// testable without network access.
internal protocol HTTPTransport: Sendable {
    /// Executes a prepared URL request.
    /// - Parameter request: The fully configured URL request.
    /// - Returns: The raw response data and URL response.
    /// - Throws: An underlying transport error.
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

/// Default transport backed by an ephemeral `URLSession`.
///
/// `URLSession` is documented as thread-safe, so this value may be shared across concurrency
/// domains. The unchecked conformance covers Foundation's lack of an explicit `Sendable`
/// annotation on some deployment targets.
internal struct URLSessionTransport: HTTPTransport, @unchecked Sendable {
    private let session: URLSession

    /// Creates a transport around the supplied session.
    /// - Parameter session: The URL session used to execute requests.
    internal init(session: URLSession) {
        self.session = session
    }

    internal func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}
