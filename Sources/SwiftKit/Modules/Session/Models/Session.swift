import Foundation

/// Represents an authenticated user session managed by the SDK.
///
/// A session bundles the bearer access token, an optional refresh token, and the absolute
/// expiration date. Instances are value types and safe to pass across concurrency domains.
public struct Session: Codable, Equatable, Sendable {
    /// The bearer access token used to authorize API requests.
    public let accessToken: String

    /// The optional refresh token used to obtain a new access token.
    public let refreshToken: String?

    /// The absolute date at which the session expires.
    public let expiresAt: Date

    /// The optional identifier of the authenticated user.
    public let userID: String?

    /// Creates a session value.
    /// - Parameters:
    ///   - accessToken: The bearer access token.
    ///   - refreshToken: An optional refresh token used to renew the session.
    ///   - expiresAt: The absolute expiration date for the session.
    ///   - userID: An optional authenticated user identifier.
    public init(
        accessToken: String,
        refreshToken: String? = nil,
        expiresAt: Date,
        userID: String? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.userID = userID
    }

    /// Indicates whether the session has expired relative to the supplied reference date.
    /// - Parameter date: The reference date to compare against.
    /// - Returns: `true` when `expiresAt` is earlier than or equal to `date`; otherwise `false`.
    public func isExpired(at date: Date) -> Bool {
        expiresAt <= date
    }
}
