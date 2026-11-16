import Foundation

/// Opaque token identifying a connectivity observer registration.
///
/// Retain the token returned by ``ConnectivityMonitorProtocol/addObserver(_:)`` so the observer can
/// later be removed through ``ConnectivityMonitorProtocol/removeObserver(_:)``.
public struct ConnectivityObservationToken: Hashable, Sendable {
    internal let id: UUID

    internal init(id: UUID = UUID()) {
        self.id = id
    }

    /// Compares two observation tokens by their underlying identifier.
    /// - Parameters:
    ///   - lhs: The left-hand token.
    ///   - rhs: The right-hand token.
    /// - Returns: `true` when both tokens identify the same registration.
    public static func == (lhs: ConnectivityObservationToken, rhs: ConnectivityObservationToken) -> Bool {
        lhs.id == rhs.id
    }

    /// Hashes the token's underlying identifier.
    /// - Parameter hasher: The hasher to feed.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
