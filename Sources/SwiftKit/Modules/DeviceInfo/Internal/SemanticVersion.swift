import Foundation

/// Internal numeric version representation supporting semantic comparison.
internal struct SemanticVersion: Comparable, Sendable {
    internal let components: [Int]

    /// Parses a dotted numeric version string such as `"1.10.2"`.
    /// Pre-release suffixes are ignored (for example, `"1.0.0-beta"` becomes `[1, 0, 0]`).
    /// - Parameter string: The version string to parse.
    /// - Returns: `nil` when the string is empty or contains non-numeric components.
    internal init?(_ string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let core = trimmed.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? trimmed
        let parts = core.split(separator: ".", omittingEmptySubsequences: false)

        var components: [Int] = []
        for part in parts {
            guard let value = Int(part) else {
                return nil
            }
            components.append(value)
        }

        guard !components.isEmpty else {
            return nil
        }

        self.components = components
    }

    /// Creates a version from explicit components.
    /// - Parameters:
    ///   - major: The major component.
    ///   - minor: The minor component.
    ///   - patch: The patch component.
    internal init(major: Int, minor: Int, patch: Int) {
        self.components = [major, minor, patch]
    }

    /// Extracts the first dotted numeric token from an arbitrary string.
    /// Useful for strings such as `"Version 18.1 (Build 22B83)"`.
    /// - Parameter string: The source string to scan.
    /// - Returns: `nil` when no numeric token is found.
    internal init?(extractingFrom string: String) {
        var token = ""
        for character in string {
            if character.isNumber || character == "." {
                token.append(character)
            } else if !token.isEmpty {
                break
            }
        }

        while token.hasSuffix(".") {
            token.removeLast()
        }

        self.init(token)
    }

    internal static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let lhsValue = index < lhs.components.count ? lhs.components[index] : 0
            let rhsValue = index < rhs.components.count ? rhs.components[index] : 0
            if lhsValue != rhsValue {
                return false
            }
        }
        return true
    }

    internal static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let lhsValue = index < lhs.components.count ? lhs.components[index] : 0
            let rhsValue = index < rhs.components.count ? rhs.components[index] : 0
            if lhsValue != rhsValue {
                return lhsValue < rhsValue
            }
        }
        return false
    }
}
