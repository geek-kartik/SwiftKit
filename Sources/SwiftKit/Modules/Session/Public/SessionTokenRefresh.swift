import Foundation

/// The credentials returned by a successful token refresh.
///
/// A ``SessionTokenRefreshHandler`` produces this value to describe the renewed access token and
/// its expiration. The session manager combines it with the existing session's user identifier to
/// build the refreshed ``Session``.
public struct SessionTokenRefresh: Equatable, Sendable {
    /// The new bearer access token.
    public let accessToken: String

    /// An optional new refresh token. When `nil`, the existing refresh token is preserved.
    public let refreshToken: String?

    /// The absolute date at which the refreshed session expires.
    public let expiresAt: Date

    /// Creates a token-refresh result.
    /// - Parameters:
    ///   - accessToken: The new bearer access token.
    ///   - refreshToken: An optional new refresh token.
    ///   - expiresAt: The absolute expiration date for the refreshed session.
    public init(accessToken: String, refreshToken: String? = nil, expiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }
}
