import Foundation

/// An immutable description of an HTTP request issued by ``NetworkClientProtocol``.
///
/// Requests may target an absolute URL, or a relative path that is resolved against the
/// `baseURL` supplied in ``NetworkConfiguration``. A relative `path` is appended to the
/// configured base URL, preserving any path prefix it contains.
public struct NetworkRequest: Sendable, Equatable {
    /// The request URL.
    ///
    /// When `url` has no scheme, it is treated as a relative path and resolved against the
    /// configured ``NetworkConfiguration/baseURL`` when the request is sent.
    public let url: URL

    /// The HTTP method used to send the request.
    public let method: HTTPMethod

    /// Request-specific HTTP headers. These override matching default headers configured
    /// on ``NetworkConfiguration`` using case-insensitive field-name matching.
    public let headers: [String: String]

    /// The raw request body, when one is required.
    ///
    /// Use ``withJSONBody(_:using:)`` to encode a `Codable` value and set the
    /// `Content-Type` header automatically.
    public let body: Data?

    /// An optional request-level timeout in seconds overriding ``NetworkConfiguration/timeoutInterval``.
    public let timeoutInterval: TimeInterval?

    /// An optional request-level cache policy overriding ``NetworkConfiguration/cachePolicy``.
    public let cachePolicy: URLRequest.CachePolicy?

    /// Creates a request targeting the supplied URL.
    /// - Parameters:
    ///   - url: An absolute URL, or a relative URL resolved against the configured base URL.
    ///   - method: The HTTP method. Defaults to `.get`.
    ///   - headers: Request-specific headers. Defaults to an empty dictionary.
    ///   - body: The raw request body. Defaults to `nil`.
    ///   - timeoutInterval: A request-level timeout override in seconds. Defaults to `nil`.
    ///   - cachePolicy: A request-level cache policy override. Defaults to `nil`.
    public init(
        url: URL,
        method: HTTPMethod = .get,
        headers: [String: String] = [:],
        body: Data? = nil,
        timeoutInterval: TimeInterval? = nil,
        cachePolicy: URLRequest.CachePolicy? = nil
    ) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
        self.timeoutInterval = timeoutInterval
        self.cachePolicy = cachePolicy
    }

    /// Creates a request from a relative path and optional query items.
    ///
    /// The resulting URL has no scheme and is resolved against
    /// ``NetworkConfiguration/baseURL`` when sent.
    /// - Parameters:
    ///   - path: A relative path such as `"/v1/accounts"`, optionally containing a query string.
    ///   - method: The HTTP method. Defaults to `.get`.
    ///   - headers: Request-specific headers. Defaults to an empty dictionary.
    ///   - queryItems: Additional query items appended to the path. Defaults to an empty array.
    ///   - body: The raw request body. Defaults to `nil`.
    ///   - timeoutInterval: A request-level timeout override in seconds. Defaults to `nil`.
    ///   - cachePolicy: A request-level cache policy override. Defaults to `nil`.
    /// - Throws: ``NetworkError/invalidURL`` when the path cannot form a URL.
    public init(
        path: String,
        method: HTTPMethod = .get,
        headers: [String: String] = [:],
        queryItems: [URLQueryItem] = [],
        body: Data? = nil,
        timeoutInterval: TimeInterval? = nil,
        cachePolicy: URLRequest.CachePolicy? = nil
    ) throws {
        guard var components = URLComponents(string: path) else {
            throw NetworkError.invalidURL
        }

        if !queryItems.isEmpty {
            components.queryItems = (components.queryItems ?? []) + queryItems
        }

        guard let url = components.url else {
            throw NetworkError.invalidURL
        }

        self.init(
            url: url,
            method: method,
            headers: headers,
            body: body,
            timeoutInterval: timeoutInterval,
            cachePolicy: cachePolicy
        )
    }

    /// Returns a header value using case-insensitive field-name matching.
    /// - Parameter name: The header field name to look up.
    /// - Returns: The matching header value, or `nil` when absent.
    public func header(named name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    /// Returns a copy with a single header set, replacing any case-insensitive match.
    /// - Parameters:
    ///   - name: The header field name.
    ///   - value: The header field value.
    /// - Returns: A copy carrying the updated header.
    public func withHeader(_ name: String, value: String) -> NetworkRequest {
        var updatedHeaders = headers

        for key in updatedHeaders.keys where key.caseInsensitiveCompare(name) == .orderedSame {
            updatedHeaders.removeValue(forKey: key)
        }

        updatedHeaders[name] = value

        return NetworkRequest(
            url: url,
            method: method,
            headers: updatedHeaders,
            body: body,
            timeoutInterval: timeoutInterval,
            cachePolicy: cachePolicy
        )
    }

    /// Returns a copy with several headers set, replacing case-insensitive matches.
    /// - Parameter additionalHeaders: The headers to merge into the request.
    /// - Returns: A copy carrying the merged headers.
    public func withHeaders(_ additionalHeaders: [String: String]) -> NetworkRequest {
        additionalHeaders.reduce(self) { request, header in
            request.withHeader(header.key, value: header.value)
        }
    }

    /// Returns a copy whose body is the JSON encoding of the supplied value.
    ///
    /// A `Content-Type: application/json` header is added unless a content type is already
    /// present. The supplied encoder is used as-is; create a new encoder per call.
    /// - Parameters:
    ///   - body: The encodable value to serialize.
    ///   - encoder: The JSON encoder used for serialization. Defaults to a new `JSONEncoder`.
    /// - Returns: A copy carrying the encoded body.
    /// - Throws: ``NetworkError/encodingFailed`` when encoding fails.
    public func withJSONBody<Body: Encodable>(
        _ body: Body,
        using encoder: JSONEncoder = JSONEncoder()
    ) throws -> NetworkRequest {
        let encodedBody: Data
        do {
            encodedBody = try encoder.encode(body)
        } catch {
            throw NetworkError.encodingFailed
        }

        var updatedHeaders = headers
        if header(named: "Content-Type") == nil {
            updatedHeaders["Content-Type"] = "application/json"
        }

        return NetworkRequest(
            url: url,
            method: method,
            headers: updatedHeaders,
            body: encodedBody,
            timeoutInterval: timeoutInterval,
            cachePolicy: cachePolicy
        )
    }
}
