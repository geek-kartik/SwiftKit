import Foundation

/// Production ``NetworkClientProtocol`` implementation backed by `URLSession`.
///
/// Request construction, header merging, status validation, and error normalization happen
/// here. Sensitive values (URLs, headers, bodies, and response payloads) are never logged.
internal final class URLSessionNetworkClient: NetworkClientProtocol, Sendable {
    internal let configuration: NetworkConfiguration

    private let transport: HTTPTransport
    private let logger: LoggerProtocol
    private let inspector: NetworkTransactionRecording?

    /// Creates a client using an ephemeral `URLSession`.
    /// - Parameters:
    ///   - configuration: The networking configuration.
    ///   - logger: Logger receiving redacted request diagnostics.
    ///   - inspector: Optional transaction sink for the SDK network inspector.
    internal convenience init(
        configuration: NetworkConfiguration = .default,
        logger: LoggerProtocol,
        inspector: NetworkTransactionRecording? = nil
    ) {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.timeoutIntervalForRequest = configuration.timeoutInterval
        sessionConfiguration.requestCachePolicy = configuration.cachePolicy
        sessionConfiguration.urlCache = nil

        let session = URLSession(configuration: sessionConfiguration)
        self.init(
            configuration: configuration,
            logger: logger,
            transport: URLSessionTransport(session: session),
            inspector: inspector
        )
    }

    /// Creates a client with an injected transport for unit testing.
    /// - Parameters:
    ///   - configuration: The networking configuration.
    ///   - logger: Logger receiving redacted request diagnostics.
    ///   - transport: The transport used to execute prepared requests.
    ///   - inspector: Optional transaction sink for the SDK network inspector.
    internal init(
        configuration: NetworkConfiguration,
        logger: LoggerProtocol,
        transport: HTTPTransport,
        inspector: NetworkTransactionRecording? = nil
    ) {
        self.configuration = configuration
        self.logger = logger
        self.transport = transport
        self.inspector = inspector
    }

    internal func send(_ request: NetworkRequest) async throws -> NetworkResponse {
        let startedAt = Date()

        guard !Task.isCancelled else {
            await capture(
                urlRequest: nil,
                request: request,
                response: nil,
                error: .cancelled,
                startedAt: startedAt
            )
            throw NetworkError.cancelled
        }

        let urlRequest: URLRequest
        do {
            urlRequest = try makeURLRequest(from: request)
        } catch {
            let networkError = NetworkError.normalized(from: error)
            await capture(
                urlRequest: nil,
                request: request,
                response: nil,
                error: networkError,
                startedAt: startedAt
            )
            throw networkError
        }

        let host = urlRequest.url?.host ?? "unknown"

        let data: Data
        let urlResponse: URLResponse
        do {
            (data, urlResponse) = try await transport.data(for: urlRequest)
        } catch {
            let networkError = NetworkError.normalized(from: error)
            await capture(
                urlRequest: urlRequest,
                request: request,
                response: nil,
                error: networkError,
                startedAt: startedAt
            )
            logOutcome(
                .failure(networkError),
                urlRequest: urlRequest,
                response: nil,
                startedAt: startedAt,
                summary: "\(request.method.rawValue) \(host) failed: \(networkError.logDescription)"
            )
            throw networkError
        }

        guard let httpResponse = urlResponse as? HTTPURLResponse else {
            await capture(
                urlRequest: urlRequest,
                request: request,
                response: nil,
                error: .invalidResponse,
                startedAt: startedAt
            )
            logOutcome(
                .failure(.invalidResponse),
                urlRequest: urlRequest,
                response: nil,
                startedAt: startedAt,
                summary: "\(request.method.rawValue) \(host) failed: invalidResponse"
            )
            throw NetworkError.invalidResponse
        }

        let response = NetworkResponse(
            statusCode: httpResponse.statusCode,
            headers: Self.headers(from: httpResponse),
            data: data,
            url: httpResponse.url
        )

        let elapsedMilliseconds = String(format: "%.0f", Date().timeIntervalSince(startedAt) * 1000)

        guard configuration.acceptableStatusCodes.contains(response.statusCode) else {
            let networkError = NetworkError.httpStatus(response)
            await capture(
                urlRequest: urlRequest,
                request: request,
                response: response,
                error: networkError,
                startedAt: startedAt
            )
            logOutcome(
                .unacceptedStatus,
                urlRequest: urlRequest,
                response: response,
                startedAt: startedAt,
                summary: "\(request.method.rawValue) \(host) -> \(response.statusCode) in \(elapsedMilliseconds) ms"
            )
            throw networkError
        }

        await capture(
            urlRequest: urlRequest,
            request: request,
            response: response,
            error: nil,
            startedAt: startedAt
        )
        logOutcome(
            .success,
            urlRequest: urlRequest,
            response: response,
            startedAt: startedAt,
            summary: "\(request.method.rawValue) \(host) -> \(response.statusCode) in \(elapsedMilliseconds) ms"
        )
        return response
    }

    /// Publishes a transaction to the inspector and error callbacks, using the prepared request
    /// when one exists.
    private func capture(
        urlRequest: URLRequest?,
        request: NetworkRequest,
        response: NetworkResponse?,
        error: NetworkError?,
        startedAt: Date
    ) async {
        let headers = urlRequest?.allHTTPHeaderFields ?? request.headers
        let body = urlRequest?.httpBody ?? request.body

        let transaction = NetworkTransaction(
            startedAt: startedAt,
            duration: Date().timeIntervalSince(startedAt),
            request: NetworkTransaction.Request(
                method: request.method,
                url: urlRequest?.url ?? request.url,
                headers: headers,
                body: body.map { NetworkTransaction.Body(data: $0) }
            ),
            response: response.map {
                NetworkTransaction.Response(
                    statusCode: $0.statusCode,
                    headers: $0.headers,
                    body: NetworkTransaction.Body(data: $0.data)
                )
            },
            error: error
        )

        inspector?.record(transaction)
        await configuration.notify(transaction: transaction)
    }

    /// Emits the configured level of request diagnostics.
    ///
    /// `.summary` keeps the historical single line, `.verbose` prints the formatted transaction
    /// block, and `.off` suppresses networking logs entirely (including send failures).
    private func logOutcome(
        _ outcome: NetworkLogFormatter.Outcome,
        urlRequest: URLRequest,
        response: NetworkResponse?,
        startedAt: Date,
        summary: String
    ) {
        let messages: [String]
        switch configuration.logVerbosity {
        case .off:
            return
        case .summary:
            messages = [summary]
        case .verbose:
            let block = NetworkLogFormatter.verboseEntry(
                request: urlRequest,
                response: response,
                outcome: outcome,
                duration: Date().timeIntervalSince(startedAt),
                maxBodyBytes: configuration.maxLoggedBodyBytes
            )
            messages = NetworkLogFormatter.chunks(of: block)
        }

        for message in messages {
            switch outcome {
            case .success:
                logger.info(message)
            case .unacceptedStatus:
                logger.warning(message)
            case .failure:
                logger.error(message)
            }
        }
    }

    /// Builds a `URLRequest`, validating the request and resolving relative URLs.
    /// - Parameter request: The public request description.
    /// - Returns: A prepared URL request.
    /// - Throws: ``NetworkError`` when the request or configuration is invalid.
    private func makeURLRequest(from request: NetworkRequest) throws -> URLRequest {
        guard configuration.timeoutInterval.isFinite, configuration.timeoutInterval > 0 else {
            throw NetworkError.invalidConfiguration(
                reason: "timeoutInterval must be a finite value greater than zero."
            )
        }

        guard request.method.allowsRequestBody || request.body == nil else {
            throw NetworkError.invalidRequest(
                reason: "\(request.method.rawValue) requests must not include a body."
            )
        }

        if let timeoutInterval = request.timeoutInterval {
            guard timeoutInterval.isFinite, timeoutInterval > 0 else {
                throw NetworkError.invalidRequest(
                    reason: "timeoutInterval must be a finite value greater than zero."
                )
            }
        }

        let url = try resolveURL(request.url)
        var urlRequest = URLRequest(
            url: url,
            cachePolicy: request.cachePolicy ?? configuration.cachePolicy,
            timeoutInterval: request.timeoutInterval ?? configuration.timeoutInterval
        )
        urlRequest.httpMethod = request.method.rawValue

        for (field, value) in configuration.defaultHeaders {
            urlRequest.setValue(value, forHTTPHeaderField: field)
        }

        for (field, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: field)
        }

        if let body = request.body {
            urlRequest.httpBody = body
        }

        return urlRequest
    }

    /// Resolves an absolute request URL or appends a relative path to the configured base URL.
    /// - Parameter url: The request URL.
    /// - Returns: An absolute HTTP(S) URL.
    /// - Throws: ``NetworkError/invalidURL`` when resolution fails or the scheme is unsupported.
    private func resolveURL(_ url: URL) throws -> URL {
        if let scheme = url.scheme?.lowercased() {
            guard scheme == "http" || scheme == "https", url.host != nil else {
                throw NetworkError.invalidURL
            }
            return url
        }

        guard let baseURL = configuration.baseURL,
              let baseScheme = baseURL.scheme?.lowercased(),
              baseScheme == "http" || baseScheme == "https",
              baseURL.host != nil,
              let relativeComponents = URLComponents(url: url, resolvingAgainstBaseURL: false),
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw NetworkError.invalidURL
        }

        var combinedPath = baseURL.path
        if !combinedPath.hasSuffix("/") {
            combinedPath += "/"
        }

        let relativePath = relativeComponents.percentEncodedPath
        combinedPath += relativePath.hasPrefix("/")
            ? String(relativePath.dropFirst())
            : relativePath

        if !combinedPath.hasPrefix("/") {
            combinedPath = "/" + combinedPath
        }

        components.percentEncodedPath = combinedPath
        components.percentEncodedQuery = relativeComponents.percentEncodedQuery
        components.percentEncodedFragment = relativeComponents.percentEncodedFragment

        guard let resolvedURL = components.url,
              let resolvedScheme = resolvedURL.scheme?.lowercased(),
              resolvedScheme == "http" || resolvedScheme == "https",
              resolvedURL.host != nil else {
            throw NetworkError.invalidURL
        }

        return resolvedURL
    }

    /// Converts platform response headers into a string dictionary.
    /// - Parameter response: The HTTP response.
    /// - Returns: A dictionary of header field names and values.
    private static func headers(from response: HTTPURLResponse) -> [String: String] {
        var headers: [String: String] = [:]

        for (key, value) in response.allHeaderFields {
            guard let name = key as? String else {
                continue
            }

            if let stringValue = value as? String {
                headers[name] = stringValue
            } else {
                headers[name] = String(describing: value)
            }
        }

        return headers
    }
}
