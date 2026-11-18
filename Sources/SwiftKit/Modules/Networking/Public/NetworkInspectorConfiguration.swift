import Foundation

/// Settings for the SDK-provided network inspector.
///
/// The inspector records every transaction that passes through ``NetworkClientProtocol`` so a
/// debug screen can show the full session history, including headers, bodies, timing, and a
/// copy-as-cURL export. It is disabled by default and intended for development builds only.
public struct NetworkInspectorConfiguration: Sendable, Equatable {
    /// Controls whether credential header values are shown and exported verbatim.
    public enum SensitiveDataPolicy: String, Sendable, Equatable, CaseIterable {
        /// Replaces credential headers with `[REDACTED]` in both the UI and cURL exports.
        ///
        /// This is the safe default: copied commands are informative but need a fresh token
        /// before they can be replayed.
        case redact

        /// Shows and exports header values exactly as they were sent.
        ///
        /// Use only in local development with non-production credentials, because copied cURL
        /// commands contain live bearer tokens.
        case include
    }

    /// A configuration that records nothing.
    public static let disabled = NetworkInspectorConfiguration(isEnabled: false)

    /// A configuration suitable for local debugging: 200 transactions, 32 KB bodies, redacted.
    public static let `default` = NetworkInspectorConfiguration()

    /// Whether transactions are captured. Defaults to `false`.
    public let isEnabled: Bool

    /// The maximum number of transactions retained in the session history.
    ///
    /// Older transactions are discarded once the limit is reached. Defaults to `200`.
    public let maxTransactions: Int

    /// The maximum bytes retained from each request or response body.
    ///
    /// Bodies larger than this value are stored truncated and flagged in the UI.
    /// Defaults to `32_768` bytes (32 KB).
    public let maxBodyBytes: Int

    /// Whether credential headers are displayed and exported verbatim. Defaults to `.redact`.
    public let sensitiveDataPolicy: SensitiveDataPolicy

    /// Creates an inspector configuration.
    /// - Parameters:
    ///   - isEnabled: Whether to capture transactions. Defaults to `false`.
    ///   - maxTransactions: The session retention limit. Defaults to `200`.
    ///   - maxBodyBytes: The per-body capture limit in bytes. Defaults to `32_768`.
    ///   - sensitiveDataPolicy: Whether credentials are redacted. Defaults to `.redact`.
    public init(
        isEnabled: Bool = false,
        maxTransactions: Int = 200,
        maxBodyBytes: Int = 32_768,
        sensitiveDataPolicy: SensitiveDataPolicy = .redact
    ) {
        self.isEnabled = isEnabled
        self.maxTransactions = maxTransactions
        self.maxBodyBytes = maxBodyBytes
        self.sensitiveDataPolicy = sensitiveDataPolicy
    }

    /// Validates the inspector settings.
    /// - Throws: ``NetworkError/invalidConfiguration(reason:)`` when a rule is violated.
    internal func validate() throws {
        guard maxTransactions >= 1 else {
            throw NetworkError.invalidConfiguration(
                reason: "inspector.maxTransactions must be at least 1."
            )
        }

        guard maxBodyBytes >= 0 else {
            throw NetworkError.invalidConfiguration(
                reason: "inspector.maxBodyBytes must be zero or greater."
            )
        }
    }
}
