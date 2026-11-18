import Foundation

/// Operational settings governing the SwiftKit networking module.
///
/// The configuration is immutable and `Sendable`. JSON encoder and decoder instances are
/// created on demand through the supplied factories because Foundation's coders are not
/// thread-safe and must not be shared across concurrent requests.
public struct NetworkConfiguration: Sendable {
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
    ///   - decoderFactory: A factory producing a fresh JSON decoder. Defaults to `JSONDecoder()`.
    ///   - encoderFactory: A factory producing a fresh JSON encoder. Defaults to `JSONEncoder()`.
    public init(
        baseURL: URL? = nil,
        defaultHeaders: [String: String] = [:],
        timeoutInterval: TimeInterval = 30,
        acceptableStatusCodes: Range<Int> = 200..<300,
        cachePolicy: URLRequest.CachePolicy = .reloadIgnoringLocalCacheData,
        decoderFactory: @escaping @Sendable () -> JSONDecoder = { JSONDecoder() },
        encoderFactory: @escaping @Sendable () -> JSONEncoder = { JSONEncoder() }
    ) {
        self.baseURL = baseURL
        self.defaultHeaders = defaultHeaders
        self.timeoutInterval = timeoutInterval
        self.acceptableStatusCodes = acceptableStatusCodes
        self.cachePolicy = cachePolicy
        self.decoderFactory = decoderFactory
        self.encoderFactory = encoderFactory
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
