import Foundation

/// Performs the backend token exchange required to renew an expired or expiring session.
///
/// Client applications supply a handler through ``SwiftKitConfiguration`` so the session manager can
/// refresh credentials without depending on a concrete networking implementation. The handler is
/// responsible for contacting the authentication backend and mapping its response to a
/// ``SessionTokenRefresh``.
///
/// - Note: Implementations should honor cooperative cancellation. When the refresh task is cancelled
///   (for example, on logout), the thrown error is surfaced as ``SessionError/refreshCancelled``.
public protocol SessionTokenRefreshHandler: Sendable {
    /// Exchanges a refresh token for a new set of credentials.
    /// - Parameter refreshToken: The stored refresh token to exchange.
    /// - Returns: The renewed credentials.
    /// - Throws: Any error encountered while refreshing; surfaced as ``SessionError/refreshFailed``.
    func refresh(using refreshToken: String) async throws -> SessionTokenRefresh
}
