import Foundation

/// Shared HTTP status and size formatting for diagnostics.
internal enum HTTPStatusText {
    /// A canonical reason phrase for a status code, or `"Unknown"` for unregistered codes.
    /// - Parameter statusCode: The HTTP status code.
    /// - Returns: The reason phrase.
    internal static func reasonPhrase(for statusCode: Int) -> String {
        switch statusCode {
        case 100: return "Continue"
        case 101: return "Switching Protocols"
        case 200: return "OK"
        case 201: return "Created"
        case 202: return "Accepted"
        case 204: return "No Content"
        case 206: return "Partial Content"
        case 301: return "Moved Permanently"
        case 302: return "Found"
        case 304: return "Not Modified"
        case 307: return "Temporary Redirect"
        case 308: return "Permanent Redirect"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 408: return "Request Timeout"
        case 409: return "Conflict"
        case 413: return "Payload Too Large"
        case 415: return "Unsupported Media Type"
        case 422: return "Unprocessable Entity"
        case 425: return "Too Early"
        case 429: return "Too Many Requests"
        case 500: return "Internal Server Error"
        case 501: return "Not Implemented"
        case 502: return "Bad Gateway"
        case 503: return "Service Unavailable"
        case 504: return "Gateway Timeout"
        default: return "Unknown"
        }
    }

    /// Formats a status code with its reason phrase, for example `404 Not Found`.
    /// - Parameter statusCode: The HTTP status code.
    /// - Returns: The formatted status line.
    internal static func statusLine(_ statusCode: Int) -> String {
        "\(statusCode) \(reasonPhrase(for: statusCode))"
    }

    /// Formats a byte count as `B`, `KB`, or `MB`.
    /// - Parameter bytes: The number of bytes.
    /// - Returns: A compact human-readable size.
    internal static func byteCount(_ bytes: Int) -> String {
        if bytes < 1_024 {
            return "\(bytes) B"
        }

        let kilobytes = Double(bytes) / 1_024
        if kilobytes < 1_024 {
            return String(format: "%.1f KB", kilobytes)
        }

        return String(format: "%.1f MB", kilobytes / 1_024)
    }

    /// Formats a duration as whole milliseconds.
    /// - Parameter duration: The duration in seconds.
    /// - Returns: A string such as `42 ms`.
    internal static func milliseconds(_ duration: TimeInterval) -> String {
        String(format: "%.0f ms", duration * 1_000)
    }
}
