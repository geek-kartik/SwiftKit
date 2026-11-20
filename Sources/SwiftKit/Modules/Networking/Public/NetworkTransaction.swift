import Foundation

/// A complete, structured record of one HTTP transaction handled by ``NetworkClientProtocol``.
///
/// Transactions are created for failed requests and passed to ``NetworkConfiguration/onError``
/// and ``NetworkConfiguration/onAuthenticationFailure``. They keep the resolved URL, merged
/// headers, and raw bodies so an app can present diagnostics or generate an equivalent cURL
/// command.
public struct NetworkTransaction: Identifiable, Sendable, Equatable {
    public enum SensitiveDataPolicy: Sendable { case redact, include }
    /// A captured request body.
    ///
    /// Bodies above the configured capture limit are stored truncated. ``totalByteCount`` keeps
    /// the original size so the UI can explain what is missing.
    public struct Body: Sendable, Equatable {
        /// The captured bytes, possibly truncated.
        public let data: Data

        /// The original body size in bytes before capture limits were applied.
        public let totalByteCount: Int

        /// Whether the captured bytes are shorter than the original body.
        public var isTruncated: Bool {
            data.count < totalByteCount
        }

        /// The captured body as UTF-8 text, or `nil` for binary payloads.
        public var text: String? {
            String(data: data, encoding: .utf8)
        }

        /// Creates a captured body.
        /// - Parameters:
        ///   - data: The captured bytes.
        ///   - totalByteCount: The original size. Defaults to the captured byte count.
        public init(data: Data, totalByteCount: Int? = nil) {
            self.data = data
            self.totalByteCount = max(data.count, totalByteCount ?? data.count)
        }

        /// Returns a copy clipped to the supplied limit while preserving the original size.
        /// - Parameter maxBytes: The maximum retained bytes.
        /// - Returns: A body no larger than `maxBytes`.
        internal func limited(toBodyBytes maxBytes: Int) -> Body {
            let limit = max(0, maxBytes)
            guard data.count > limit else { return self }
            return Body(data: data.prefix(limit), totalByteCount: totalByteCount)
        }
    }

    /// The outgoing half of a transaction.
    public struct Request: Sendable, Equatable {
        /// The HTTP method.
        public let method: HTTPMethod

        /// The fully resolved URL, including any query string.
        public let url: URL

        /// The merged headers actually sent, including configuration defaults.
        public let headers: [String: String]

        /// The request body, when one was sent.
        public let body: Body?

        /// Creates a captured request.
        /// - Parameters:
        ///   - method: The HTTP method.
        ///   - url: The resolved request URL.
        ///   - headers: The merged request headers.
        ///   - body: The raw body, or `nil` when the request had none.
        public init(
            method: HTTPMethod,
            url: URL,
            headers: [String: String] = [:],
            body: Body? = nil
        ) {
            self.method = method
            self.url = url
            self.headers = headers
            self.body = body
        }

        internal func limited(toBodyBytes maxBytes: Int) -> Request {
            Request(
                method: method,
                url: url,
                headers: headers,
                body: body?.limited(toBodyBytes: maxBytes)
            )
        }
    }

    /// The incoming half of a transaction.
    public struct Response: Sendable, Equatable {
        /// The HTTP status code.
        public let statusCode: Int

        /// The response headers.
        public let headers: [String: String]

        /// The response body, captured up to the configured limit.
        public let body: Body

        /// Creates a captured response.
        /// - Parameters:
        ///   - statusCode: The HTTP status code.
        ///   - headers: The response headers.
        ///   - body: The raw response body.
        public init(statusCode: Int, headers: [String: String] = [:], body: Body) {
            self.statusCode = statusCode
            self.headers = headers
            self.body = body
        }

        internal func limited(toBodyBytes maxBytes: Int) -> Response {
            Response(
                statusCode: statusCode,
                headers: headers,
                body: body.limited(toBodyBytes: maxBytes)
            )
        }
    }

    /// Stable identifier used by list diffing and detail navigation.
    public let id: UUID

    /// When the request started.
    public let startedAt: Date

    /// Wall-clock duration of the transaction in seconds.
    public let duration: TimeInterval

    /// The captured request.
    public let request: Request

    /// The captured response, when the server replied.
    public let response: Response?

    /// The normalized failure, when the transaction did not complete successfully.
    public let error: NetworkError?

    /// Creates a transaction record.
    /// - Parameters:
    ///   - id: A stable identifier. Defaults to a new `UUID`.
    ///   - startedAt: The request start time.
    ///   - duration: The elapsed time in seconds.
    ///   - request: The captured request.
    ///   - response: The captured response, if one was received.
    ///   - error: The normalized failure, if any.
    public init(
        id: UUID = UUID(),
        startedAt: Date,
        duration: TimeInterval,
        request: Request,
        response: Response? = nil,
        error: NetworkError? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.duration = duration
        self.request = request
        self.response = response
        self.error = error
    }

    /// The HTTP status code, whether it came from a response or an `.httpStatus` error.
    public var statusCode: Int? {
        response?.statusCode ?? error?.statusCode
    }

    /// Whether the transaction completed without an error.
    public var isSuccess: Bool {
        error == nil && response != nil
    }

    /// Whether the failure is considered transient by ``NetworkError/isRetryable``.
    public var isRetryable: Bool {
        error?.isRetryable ?? false
    }

    /// Whether the failure represents an authentication or authorization rejection.
    public var isAuthenticationFailure: Bool {
        error?.isAuthenticationFailure ?? false
    }

    /// A human-readable failure description, or `nil` for successful transactions.
    public var errorDescription: String? {
        error?.errorDescription
    }

    /// The duration formatted in milliseconds.
    public var durationText: String {
        HTTPStatusText.milliseconds(duration)
    }

    /// The request path and query, suitable for a compact list row.
    public var pathText: String {
        var text = request.url.path
        if let query = request.url.query, !query.isEmpty {
            text += "?" + query
        }
        return text.isEmpty ? request.url.absoluteString : text
    }

    /// A redacted cURL command equivalent to the captured request.
    ///
    /// Credential headers are replaced with `[REDACTED]`. To export the real values, call
    /// ``curlCommand(sensitiveDataPolicy:)`` with `.include`, or enable `.include` in
    /// ``NetworkInspectorConfiguration``.
    public var curlCommand: String {
        curlCommand(sensitiveDataPolicy: .redact)
    }

    /// A cURL command equivalent to the captured request.
    ///
    /// The command includes the method, resolved URL, every header, and the request body. Bodies
    /// that were truncated during capture, or that are not UTF-8 text, are annotated with a
    /// leading shell comment instead of producing a misleading command.
    /// - Parameter sensitiveDataPolicy: Whether credential headers are included verbatim.
    /// - Returns: A multi-line, shell-pasteable cURL command.
    public func curlCommand(
        sensitiveDataPolicy: SensitiveDataPolicy = .redact
    ) -> String {
        var lines: [String] = []
        var notices: [String] = []

        let headers = request.headers
            .sorted { $0.key.lowercased() < $1.key.lowercased() }
        var parts: [String] = [
            "curl -X \(request.method.rawValue) \(Self.shellQuoted(request.url.absoluteString))"
        ]

        for (name, value) in headers {
            let shown = sensitiveDataPolicy == .redact && SensitiveHeaders.isSensitive(name)
                ? "[REDACTED]"
                : value
            parts.append("-H \(Self.shellQuoted("\(name): \(shown)"))")
        }

        if let body = request.body {
            if body.isTruncated {
                notices.append(
                    "# Request body truncated: showing \(body.data.count) of \(body.totalByteCount) bytes."
                )
            }

            if let text = body.text, !body.data.isEmpty {
                parts.append("--data-raw \(Self.shellQuoted(text))")
            } else if !body.data.isEmpty {
                notices.append(
                    "# Request body is not UTF-8 text and was omitted from this command."
                )
            }
        }

        lines.append(parts.joined(separator: " \\\n  "))
        return (notices + lines).joined(separator: "\n")
    }

    // MARK: - Helpers

    /// Wraps a value in single quotes for POSIX shells, escaping embedded single quotes.
    private static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Returns a copy whose bodies are clipped to a maximum capture size.
    /// - Parameter maxBytes: The maximum retained bytes per body.
    /// - Returns: A transaction suitable for storage.
    internal func limited(toBodyBytes maxBytes: Int) -> NetworkTransaction {
        NetworkTransaction(
            id: id,
            startedAt: startedAt,
            duration: duration,
            request: request.limited(toBodyBytes: maxBytes),
            response: response?.limited(toBodyBytes: maxBytes),
            error: error
        )
    }
}
