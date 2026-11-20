import Foundation

/// Header names that commonly carry credentials and must never be shown verbatim in
/// diagnostics or exported cURL commands.
internal enum SensitiveHeaders {
    /// Lowercase field names whose values are replaced with `[REDACTED]`.
    internal static let names: Set<String> = [
        "authorization",
        "proxy-authorization",
        "cookie",
        "set-cookie",
        "x-api-key",
        "x-auth-token",
        "api-key",
        "apikey",
        "x-demo-token"
    ]

    /// Whether a header field carries a credential.
    /// - Parameter name: The header field name, matched case-insensitively.
    /// - Returns: `true` when the value should be redacted.
    internal static func isSensitive(_ name: String) -> Bool {
        names.contains(name.lowercased())
    }

    /// Replaces credential header values with `[REDACTED]` while preserving names and ordering.
    /// - Parameter headers: The header dictionary to sanitize.
    /// - Returns: A dictionary safe for display or export.
    internal static func redacted(_ headers: [String: String]) -> [String: String] {
        headers.reduce(into: [:]) { result, entry in
            result[entry.key] = isSensitive(entry.key) ? "[REDACTED]" : entry.value
        }
    }
}
