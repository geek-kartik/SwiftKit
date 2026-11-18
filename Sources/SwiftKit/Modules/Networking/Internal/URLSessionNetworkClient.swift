import Foundation

/// Production ``NetworkClientProtocol`` implementation backed by `URLSession`.
///
/// Request construction, header merging, status validation, and error normalization happen
/// here. Sensitive values (URLs, headers, bodies, and response payloads) are never logged.
internal final class URLSessionNetworkClient: NetworkClientProtocol, Sendable {
    internal let configuration: NetworkConfiguration

    private let transport: HTTPTransport
    private let logger: LoggerProtocol

    /// Creates a client using an ephemeral `URLSession`.
    /// - Parameters:
    ///   - configuration: The networking configuration.
    ///   - logger: Logger receiving redacted request diagnostics.
    internal convenience init(
        configuration: NetworkConfiguration = .default,
        logger: LoggerProtocol
    ) {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.timeoutIntervalForRequest = configuration.timeoutInterval
        sessionConfiguration.requestCachePolicy = configuration.cachePolicy
        sessionConfiguration.urlCache = nil

        let session = URLSession(configuration: sessionConfiguration)
        self.init(
            configuration: configuration,
            logger: logger,
            transport: URLSessionTransport(session: session)
        )
    }

    /// Creates a client with an injected transport for unit testing.
    /// - Parameters:
    ///   - configuration: The networking configuration.
    ///   - logger: Logger receiving redacted request diagnostics.
    ///   - transport: The transport used to execute prepared requests.
    internal init(
        configuration: NetworkConfiguration,
        logger: LoggerProtocol,
        transport: HTTPTransport
    ) {
        self.configuration = configuration
        self.logger = logger
        self.transport = transport
    }

    internal func send(_ request: NetworkRequest) async throws -> NetworkResponse {
        guard !Task.isCancelled else {
            throw NetworkError.cancelled
        }

        let urlRequest = try makeURLRequest(from: request)
        let host = urlRequest.url?.host ?? "unknown"
        let startedAt = Date()

        let data: Data
        let urlResponse: URLResponse
        do {
            (data, urlResponse) = try await transport.data(for: urlRequest)
        } catch {
            let networkError = NetworkError.normalized(from: error)
            logger.error("\(request.method.rawValue) \(host) failed: \(networkError.logDescription)")
            throw networkError
        }

        guard let httpResponse = urlResponse as? HTTPURLResponse else {
            logger.error("\(request.method.rawValue) \(host) failed: invalidResponse")
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
            logger.warning(
                "\(request.method.rawValue) \(host) -> \(response.statusCode) in \(elapsedMilliseconds) ms"
            )
            throw NetworkError.httpStatus(response)
        }

        logger.info(
            "\(request.method.rawValue) \(host) -> \(response.statusCode) in \(elapsedMilliseconds) ms"
        )
        return response
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
