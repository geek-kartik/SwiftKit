import Foundation

/// Represents the system network-path connectivity state reported by Apple's `Network` framework.
///
/// - Note: A `.connected` status indicates that the system has a satisfied network path. It does not
///   guarantee that an internet connection or a specific backend is reachable.
public enum ConnectivityStatus: String, CaseIterable, Sendable {
    /// The connectivity state has not been determined yet.
    ///
    /// This is the initial status before the first network-path update is delivered. Consumers should
    /// treat it as a pending state rather than as an offline state.
    case unknown

    /// A satisfied network path is available.
    case connected

    /// No satisfied network path is currently available.
    case disconnected

    /// Whether the current status represents an available network path.
    public var isConnected: Bool {
        self == .connected
    }
}
