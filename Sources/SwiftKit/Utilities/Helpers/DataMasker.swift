import Foundation

/// Utility responsible for sanitizing and masking sensitive details before logging.
public struct DataMasker: Sendable {
    private static let sensitiveKeys: Set<String> = [
        "authorization", "password", "token", "accesstoken", "refreshtoken",
        "secret", "apikey", "api_key", "bearer", "creditcard", "ssn", "cvv"
    ]

    /// Masks common sensitive strings including tokens and credentials.
    /// - Parameter text: Raw text to sanitize.
    /// - Returns: Redacted safe string.
    public static func mask(_ text: String) -> String {
        var masked = text

        // Mask Authorization Bearer tokens: Bearer <token> -> Bearer [REDACTED]
        let bearerPattern = #"(?i)bearer\s+([A-Za-z0-9_\-\.]+)"#
        if let regex = try? NSRegularExpression(pattern: bearerPattern) {
            let range = NSRange(masked.startIndex..<masked.endIndex, in: masked)
            masked = regex.stringByReplacingMatches(in: masked, options: [], range: range, withTemplate: "Bearer [REDACTED]")
        }

        // Mask email addresses: name@example.com -> n***e@example.com
        let emailPattern = #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#
        if let emailRegex = try? NSRegularExpression(pattern: emailPattern) {
            let matches = emailRegex.matches(in: masked, options: [], range: NSRange(masked.startIndex..<masked.endIndex, in: masked))
            for match in matches.reversed() {
                if let range = Range(match.range, in: masked) {
                    let email = String(masked[range])
                    let components = email.split(separator: "@")
                    if components.count == 2 {
                        let name = components[0]
                        let domain = components[1]
                        let maskedName: String
                        if name.count > 2 {
                            let first = name.prefix(1)
                            let last = name.suffix(1)
                            maskedName = "\(first)***\(last)"
                        } else {
                            maskedName = "***"
                        }
                        masked.replaceSubrange(range, with: "\(maskedName)@\(domain)")
                    }
                }
            }
        }

        // Mask potential JSON keys matching sensitive keys
        for key in sensitiveKeys {
            let jsonPattern = "(?i)\"" + key + "\"(\\s*:\\s*\")([^\"]+)(\")"
            if let jsonRegex = try? NSRegularExpression(pattern: jsonPattern) {
                let range = NSRange(masked.startIndex..<masked.endIndex, in: masked)
                masked = jsonRegex.stringByReplacingMatches(in: masked, options: [], range: range, withTemplate: "\"\(key)\"$1********$3")
            }
        }

        return masked
    }
}
