import Foundation

/// Opaque token identifying a session observer registration.
///
/// Retain the token returned by ``SessionManagerProtocol/addObserver(_:)`` so the observer can
/// later be removed through ``SessionManagerProtocol/removeObserver(_:)``.
public struct SessionObservationToken: Hashable, Sendable {
    internal let id: UUID

    internal init(id: UUID = UUID()) {
        self.id = id
    }
}
