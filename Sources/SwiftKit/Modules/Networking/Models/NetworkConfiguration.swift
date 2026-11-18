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
    /// Verbose output is intended for local debugging in Xcode. It is emitted through the
    /// SDK's ``LoggerProtocol`` and is always passed through ``DataMasker``, but it includes
    /// request and response bodies, so keep it disabled in production builds.
    public enum LogVerbosity: String, Sendable, Equatable, CaseIterable {
        /// Disables all networking diagnostics.
        case off

        /// Logs one redacted summary line per request, for example `GET api.example.com -> 200 in 12 ms`.
        case summary

        /// Logs a formatted, multi-line request/response block with masked headers and bodies.
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

    /// The diagnostic detail written to the SDK logger for every request.
    ///
    /// Defaults to ``LogVerbosity/summary``. Use ``LogVerbosity/verbose`` while debugging in
    /// Xcode to see request/response headers and JSON bodies, and
    /// ``LogVerbosity/off`` to silence networking diagnostics entirely.
    public let logVerbosity: LogVerbosity

    /// The maximum number of bytes captured from each request or response body in verbose logs.
    ///
    /// Bodies larger than this limit are truncated with an explicit marker so the console stays
    /// readable. Set to `0` to omit body content while keeping headers and status information.
    /// Defaults to `8_192` bytes.
    public let maxLoggedBodyBytes: Int

    /// Settings for the SDK-provided session network inspector.
    ///
    /// The inspector is disabled by default. Enable it in development builds to capture every
    /// transaction for the in-app debug screen and its copy-as-cURL export.
    public let inspector: NetworkInspectorConfiguration

    /// Invoked for every failed transaction, including status, transport, validation, and
    /// decoding failures.
    ///
    /// Use this to centralize cross-cutting error handling. For example, an app can present a
    /// global banner or refresh telemetry. The callback receives the same structured
    /// ``NetworkTransaction`` that the inspector records.
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
    ///   - logVerbosity: The diagnostic detail written to the logger. Defaults to `.summary`.
    ///   - maxLoggedBodyBytes: The maximum body bytes captured by verbose logs. Defaults to `8_192`.
    ///   - inspector: Session inspector settings. Defaults to ``NetworkInspectorConfiguration/disabled``.
    ///   - onError: A callback invoked for every failed transaction. Defaults to `nil`.
    ///   - onAuthenticationFailure: A callback invoked for `401` and `403` failures. Defaults to `nil`.
    ///   - decoderFactory: A factory producing a fresh JSON decoder. Defaults to `JSONDecoder()`.
    ///   - encoderFactory: A factory producing a fresh JSON encoder. Defaults to `JSONEncoder()`.
    public init(
        baseURL: URL? = nil,
        defaultHeaders: [String: String] = [:],
        timeoutInterval: TimeInterval = 30,
        acceptableStatusCodes: Range<Int> = 200..<300,
        cachePolicy: URLRequest.CachePolicy = .reloadIgnoringLocalCacheData,
        logVerbosity: LogVerbosity = .summary,
        maxLoggedBodyBytes: Int = 8_192,
        inspector: NetworkInspectorConfiguration = .disabled,
        onError: TransactionHandler? = nil,
        onAuthenticationFailure: TransactionHandler? = nil,
        decoderFactory: @escaping @Sendable () -> JSONDecoder = { JSONDecoder() },
        encoderFactory: @escaping @Sendable () -> JSONEncoder = { JSONEncoder() }
    ) {
        self.baseURL = baseURL
        self.defaultHeaders = defaultHeaders
        self.timeoutInterval = timeoutInterval
        self.acceptableStatusCodes = acceptableStatusCodes
        self.cachePolicy = cachePolicy
        self.logVerbosity = logVerbosity
        self.maxLoggedBodyBytes = maxLoggedBodyBytes
        self.inspector = inspector
        self.onError = onError
        self.onAuthenticationFailure = onAuthenticationFailure
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

        guard maxLoggedBodyBytes >= 0 else {
            throw NetworkError.invalidConfiguration(
                reason: "maxLoggedBodyBytes must be zero or greater."
            )
        }

        try inspector.validate()
    }
}
