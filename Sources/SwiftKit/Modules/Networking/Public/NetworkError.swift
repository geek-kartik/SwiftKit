import Foundation

/// Errors produced by the SwiftKit networking layer.
///
/// All transport failures are normalized into this domain error so client applications can
/// handle networking outcomes consistently without depending on `URLError`.
public enum NetworkError: Error, LocalizedError, Equatable, Sendable {
    /// The request URL is malformed, uses an unsupported scheme, or is a relative path that
    /// could not be resolved because no base URL is configured.
    case invalidURL

    /// The supplied ``NetworkConfiguration`` is not valid.
    case invalidConfiguration(reason: String)

    /// The request is not valid, for example a `GET` request carrying a body or a
    /// non-positive timeout interval.
    case invalidRequest(reason: String)

    /// The server response was not an `HTTPURLResponse`.
    case invalidResponse

    /// The underlying transport failed with a `URLError` code that has no more specific mapping.
    case transportFailure(code: URLError.Code)

    /// The request exceeded its timeout interval.
    case timeout

    /// The request was cancelled.
    case cancelled

    /// No usable network connection is currently available.
    case noInternetConnection

    /// The response body was empty when a decoded value was requested.
    case emptyResponse

    /// The request body could not be encoded.
    case encodingFailed

    /// The response body could not be decoded.
    case decodingFailed

    /// The server returned a status code outside the accepted range.
    ///
    /// The associated response preserves the status code, headers, and raw body so callers can
    /// present or decode server-provided error payloads if needed.
    case httpStatus(NetworkResponse)

    /// A human-readable description of the networking failure.
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The request URL is invalid or could not be resolved."
        case .invalidConfiguration(let reason):
            return "Invalid network configuration: \(reason)"
        case .invalidRequest(let reason):
            return "Invalid network request: \(reason)"
        case .invalidResponse:
            return "The server response was not a valid HTTP response."
        case .transportFailure(let code):
            return "The network transport failed: \(URLError(code).localizedDescription)"
        case .timeout:
            return "The network request timed out."
        case .cancelled:
            return "The network request was cancelled."
        case .noInternetConnection:
            return "No internet connection is available."
        case .emptyResponse:
            return "The server returned an empty response body."
        case .encodingFailed:
            return "Failed to encode the request body as JSON."
        case .decodingFailed:
            return "Failed to decode the response body."
        case .httpStatus(let response):
            return "The server returned an unacceptable HTTP status code: \(response.statusCode)."
        }
    }

    /// The response carried by an ``httpStatus(_:)`` failure, if any.
    public var response: NetworkResponse? {
        guard case .httpStatus(let response) = self else {
            return nil
        }
        return response
    }

    /// The HTTP status code carried by an ``httpStatus(_:)`` failure, if any.
    public var statusCode: Int? {
        response?.statusCode
    }

    /// Whether the failure represents an authentication or authorization rejection.
    ///
    /// Returns `true` for `401 Unauthorized` and `403 Forbidden`.
    public var isAuthenticationFailure: Bool {
        guard let statusCode else {
            return false
        }
        return statusCode == 401 || statusCode == 403
    }

    /// Whether the request may reasonably be retried.
    ///
    /// Only transport-level and server-side transient failures are considered retryable.
    /// Callers remain responsible for ensuring the request is idempotent before retrying.
    public var isRetryable: Bool {
        switch self {
        case .timeout, .noInternetConnection:
            return true
        case .transportFailure(let code):
            switch code {
            case .timedOut,
                 .networkConnectionLost,
                 .notConnectedToInternet,
                 .dnsLookupFailed,
                 .cannotConnectToHost,
                 .cannotFindHost:
                return true
            default:
                return false
            }
        case .httpStatus(let response):
            return response.statusCode == 408
                || response.statusCode == 425
                || response.statusCode == 429
                || (500...599).contains(response.statusCode)
        default:
            return false
        }
    }

    /// Redacted diagnostic description that never includes URLs, headers, or payloads.
    internal var logDescription: String {
        switch self {
        case .invalidURL:
            return "invalidURL"
        case .invalidConfiguration:
            return "invalidConfiguration"
        case .invalidRequest:
            return "invalidRequest"
        case .invalidResponse:
            return "invalidResponse"
        case .transportFailure(let code):
            return "transportFailure(code: \(code.rawValue))"
        case .timeout:
            return "timeout"
        case .cancelled:
            return "cancelled"
        case .noInternetConnection:
            return "noInternetConnection"
        case .emptyResponse:
            return "emptyResponse"
        case .encodingFailed:
            return "encodingFailed"
        case .decodingFailed:
            return "decodingFailed"
        case .httpStatus(let response):
            return "httpStatus(\(response.statusCode))"
        }
    }

    /// Normalizes an arbitrary transport error into a ``NetworkError``.
    /// - Parameter error: The error thrown by the transport.
    /// - Returns: A matching domain error.
    internal static func normalized(from error: Error) -> NetworkError {
        if let networkError = error as? NetworkError {
            return networkError
        }

        if error is CancellationError {
            return .cancelled
        }

        guard let urlError = error as? URLError else {
            return .transportFailure(code: .unknown)
        }

        switch urlError.code {
        case .cancelled:
            return .cancelled
        case .timedOut:
            return .timeout
        case .notConnectedToInternet,
             .networkConnectionLost,
             .internationalRoamingOff,
             .dataNotAllowed:
            return .noInternetConnection
        case .badURL, .unsupportedURL:
            return .invalidURL
        default:
            return .transportFailure(code: urlError.code)
        }
    }
}
