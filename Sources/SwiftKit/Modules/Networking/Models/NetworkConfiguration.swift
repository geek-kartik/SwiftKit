import Foundation

/// Operational settings governing the SwiftKit networking module.
///
/// The configuration is immutable and `Sendable`. JSON encoder and decoder instances are
/// created on demand through the supplied factories because Foundation's coders are not
/// thread-safe and must not be shared across concurrent requests.
public struct NetworkConfiguration: Sendable {
    /// A callback invoked after every failed request.
    ///
    /// Handlers run inside the request's task before the error is rethrown, so application state
    /// (for example clearing a session) is updated before the caller handles the failure. Keep
    /// handlers fast; slow work delays the request's completion.
    public typealias TransactionHandler = @Sendable (NetworkTransaction) async -> Void

    /// Controls how much diagnostic detail the networking client writes to the logger.
    ///
    /// - Important: Reserved for a future logging feature. The client does not read this value,
    ///   so it currently has no effect.
    public enum LogVerbosity: String, Sendable, Equatable, CaseIterable {
        /// Disables all networking diagnostics.
        case off

        /// Reserved for a redacted one-line request summary.
        case summary

        /// Reserved for a formatted request/response block with masked headers and bodies.
        case verbose
    }

    /// Default configuration suitable for HTTPS JSON APIs.
    public static let `default` = NetworkConfiguration()

    /// The base URL used to resolve relative request paths.
    ///
    /// When `nil`, requests must supply an absolute URL.
    public let baseURL: URL?

    /// Headers applied to every request before request-specific headers are merged.
    public let defaultHeaders: [String: String]

    /// The default timeout in seconds applied to requests without a request-level override.
    public let timeoutInterval: TimeInterval

    /// The half-open range of HTTP status codes considered successful.
    public let acceptableStatusCodes: Range<Int>

    /// The default cache policy applied to requests without a request-level override.
    public let cachePolicy: URLRequest.CachePolicy

    /// Produces the URL session configuration used by the production client.
    ///
    /// Supply a factory to register custom `URLProtocol` subclasses, configure a proxy, or
    /// provide a test session. The factory must return a fresh configuration on every call;
    /// the client applies ``timeoutInterval`` and ``cachePolicy`` and disables the URL cache
    /// on the returned value.
    ///
    /// When `nil`, the client uses an ephemeral configuration.
    public let sessionConfigurationFactory: (@Sendable () -> URLSessionConfiguration)?

    /// Produces the current bearer token applied to every request.
    public let tokenProvider: (@Sendable () async -> String?)?

    /// Reserved for callers that refresh tokens outside the client.
    ///
    /// - Important: The client does not invoke this closure. Use
    ///   ``NetworkConfiguration/onAuthenticationFailure`` for auth handling and handle
    ///   refresh/retry in your app.
    public let refreshToken: (@Sendable () async throws -> Void)?

    /// Whether failure details are logged. Defaults to `false`.
    ///
    /// - Important: Reserved for a future logging feature. The client does not read this value,
    ///   so it currently has no effect.
    public let logErrorDetails: Bool

    /// Invoked for every failed transaction, including status, transport, validation, and
    /// decoding failures.
    ///
    /// Use this to centralize cross-cutting error handling. For example, an app can present a
    /// global banner or refresh telemetry. The callback receives the structured
    /// ``NetworkTransaction`` built for the failed request.
    public let onError: TransactionHandler?

    /// Invoked specifically for authentication and authorization failures (`401` and `403`).
    ///
    /// This is the recommended hook for a global sign-out flow:
    ///
    /// ```swift
    /// let network = NetworkConfiguration(
    ///     baseURL: baseURL,
    ///     onAuthenticationFailure: { transaction in
    ///         await MainActor.run { session.signOut() }
    ///     }
    /// )
    /// ```
    ///
    /// When a transaction is an authentication failure, both ``onError`` and this callback run.
    public let onAuthenticationFailure: TransactionHandler?

    /// Creates a fresh JSON decoder for each decoding operation.
    ///
    /// Override this factory to configure strategies such as
    /// `JSONDecoder.KeyDecodingStrategy.convertFromSnakeCase`.
    public let decoderFactory: @Sendable () -> JSONDecoder

    /// Creates a fresh JSON encoder for each encoding operation.
    ///
    /// Override this factory to configure strategies such as
    /// `JSONEncoder.KeyEncodingStrategy.convertToSnakeCase`.
    public let encoderFactory: @Sendable () -> JSONEncoder

    /// Creates a networking configuration.
    /// - Parameters:
    ///   - baseURL: The base URL used to resolve relative paths. Defaults to `nil`.
    ///   - defaultHeaders: Headers applied to every request. Defaults to an empty dictionary.
    ///   - timeoutInterval: The default request timeout in seconds. Defaults to `30`.
    ///   - acceptableStatusCodes: The accepted success range. Defaults to `200..<300`.
    ///   - cachePolicy: The default cache policy. Defaults to `.reloadIgnoringLocalCacheData`
    ///     because banking responses should not be reused from the local HTTP cache.
    ///   - onError: A callback invoked for every failed transaction. Defaults to `nil`.
    ///   - onAuthenticationFailure: A callback invoked for `401` and `403` failures. Defaults to `nil`.
    ///   - tokenProvider: Produces the current bearer token for each request. Defaults to `nil`.
    ///   - refreshToken: Reserved for callers that refresh tokens outside the client. Defaults to `nil`.
    ///   - logErrorDetails: Whether failure details are logged. Defaults to `false`.
    ///   - sessionConfigurationFactory: Produces the URL session configuration. Defaults to `nil`,
    ///     which uses an ephemeral configuration.
    ///   - decoderFactory: A factory producing a fresh JSON decoder. Defaults to `JSONDecoder()`.
    ///   - encoderFactory: A factory producing a fresh JSON encoder. Defaults to `JSONEncoder()`.
    public init(
        baseURL: URL? = nil,
        defaultHeaders: [String: String] = [:],
        timeoutInterval: TimeInterval = 30,
        acceptableStatusCodes: Range<Int> = 200..<300,
        cachePolicy: URLRequest.CachePolicy = .reloadIgnoringLocalCacheData,
        onError: TransactionHandler? = nil,
        onAuthenticationFailure: TransactionHandler? = nil,
        tokenProvider: (@Sendable () async -> String?)? = nil,
        refreshToken: (@Sendable () async throws -> Void)? = nil,
        logErrorDetails: Bool = false,
        sessionConfigurationFactory: (@Sendable () -> URLSessionConfiguration)? = nil,
        decoderFactory: @escaping @Sendable () -> JSONDecoder = { JSONDecoder() },
        encoderFactory: @escaping @Sendable () -> JSONEncoder = { JSONEncoder() }
    ) {
        self.baseURL = baseURL
        self.defaultHeaders = defaultHeaders
        self.timeoutInterval = timeoutInterval
        self.acceptableStatusCodes = acceptableStatusCodes
        self.cachePolicy = cachePolicy
        self.onError = onError
        self.onAuthenticationFailure = onAuthenticationFailure
        self.tokenProvider = tokenProvider
        self.refreshToken = refreshToken
        self.logErrorDetails = logErrorDetails
        self.sessionConfigurationFactory = sessionConfigurationFactory
        self.decoderFactory = decoderFactory
        self.encoderFactory = encoderFactory
    }

    /// Invokes the configured error callbacks for a failed transaction.
    /// - Parameter transaction: The failed transaction. Successful transactions are ignored.
    internal func notify(transaction: NetworkTransaction) async {
        guard let error = transaction.error else { return }

        if let onError {
            await onError(transaction)
        }

        if error.isAuthenticationFailure, let onAuthenticationFailure {
            await onAuthenticationFailure(transaction)
        }
    }

    /// Validates the configuration.
    /// - Throws: ``NetworkError/invalidConfiguration(reason:)`` when a rule is violated.
    public func validate() throws {
        if let baseURL {
            guard baseURL.scheme != nil, baseURL.host != nil else {
                throw NetworkError.invalidConfiguration(
                    reason: "baseURL must be an absolute URL with a scheme and host."
                )
            }

            guard let scheme = baseURL.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
                throw NetworkError.invalidConfiguration(
                    reason: "baseURL must use the http or https scheme."
                )
            }
        }

        guard timeoutInterval.isFinite, timeoutInterval > 0 else {
            throw NetworkError.invalidConfiguration(
                reason: "timeoutInterval must be a finite value greater than zero."
            )
        }

        guard !acceptableStatusCodes.isEmpty else {
            throw NetworkError.invalidConfiguration(
                reason: "acceptableStatusCodes must not be empty."
            )
        }

        guard acceptableStatusCodes.lowerBound >= 100, acceptableStatusCodes.upperBound <= 600 else {
            throw NetworkError.invalidConfiguration(
                reason: "acceptableStatusCodes must stay within the valid HTTP status range 100..<600."
            )
        }

    }
}
