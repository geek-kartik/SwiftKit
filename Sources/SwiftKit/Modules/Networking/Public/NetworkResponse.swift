import Foundation

/// An immutable HTTP response returned by ``NetworkClientProtocol``.
///
/// Responses are only returned for status codes accepted by
/// ``NetworkConfiguration/acceptableStatusCodes``. Unacceptable status codes are surfaced as
/// ``NetworkError/httpStatus(_:)`` carrying the same response payload for inspection.
public struct NetworkResponse: Sendable, Equatable {
    /// The HTTP status code returned by the server.
    public let statusCode: Int

    /// The response headers.
    public let headers: [String: String]

    /// The raw response body.
    public let data: Data

    /// The URL of the response, when reported by the system.
    public let url: URL?

    /// Creates a response value.
    /// - Parameters:
    ///   - statusCode: The HTTP status code.
    ///   - headers: The response headers. Defaults to an empty dictionary.
    ///   - data: The raw response body.
    ///   - url: The URL of the response. Defaults to `nil`.
    public init(
        statusCode: Int,
        headers: [String: String] = [:],
        data: Data,
        url: URL? = nil
    ) {
        self.statusCode = statusCode
        self.headers = headers
        self.data = data
        self.url = url
    }

    /// Whether the status code falls within the standard `200..<300` success range.
    ///
    /// Calling ``NetworkClientProtocol/send(_:)`` only returns responses accepted by the
    /// configured status range, which defaults to this same interval.
    public var isSuccess: Bool {
        (200..<300).contains(statusCode)
    }

    /// Returns a header value using case-insensitive field-name matching.
    /// - Parameter name: The header field name to look up.
    /// - Returns: The matching header value, or `nil` when absent.
    public func header(named name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    /// Decodes the response body into the requested type.
    /// - Parameters:
    ///   - type: The expected decoded type.
    ///   - decoder: The JSON decoder to use. Defaults to a new `JSONDecoder`.
    /// - Returns: The decoded value.
    /// - Throws: ``NetworkError/emptyResponse`` when the body is empty, or
    ///   ``NetworkError/decodingFailed`` when decoding fails.
    public func decode<Response: Decodable>(
        _ type: Response.Type,
        using decoder: JSONDecoder = JSONDecoder()
    ) throws -> Response {
        guard !data.isEmpty else {
            throw NetworkError.emptyResponse
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw NetworkError.decodingFailed
        }
    }
}
