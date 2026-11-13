import Foundation
import Network

/// Abstraction over `NWPathMonitor` so connectivity transitions can be simulated in unit tests.
internal protocol NetworkPathMonitorEngine: AnyObject, Sendable {
    /// Starts delivering path updates to the handler on the supplied queue.
    /// - Parameters:
    ///   - queue: Serial queue on which updates are delivered.
    ///   - onUpdate: Callback invoked for every path update.
    func start(queue: DispatchQueue, onUpdate: @escaping @Sendable (ConnectivityStatus) -> Void)

    /// Cancels the underlying monitor and stops delivering updates.
    func cancel()
}

/// Creates a fresh monitoring engine for each monitoring session.
internal protocol NetworkPathMonitorEngineFactory: Sendable {
    /// Creates a new engine instance.
    /// - Returns: An engine ready to be started.
    func makeEngine() -> NetworkPathMonitorEngine
}

/// Factory producing `NWPathMonitor`-backed engines.
internal struct NWPathMonitorEngineFactory: NetworkPathMonitorEngineFactory {
    internal func makeEngine() -> NetworkPathMonitorEngine {
        NWPathMonitorEngine()
    }
}

/// Concrete engine backed by Apple's `NWPathMonitor`.
///
/// - Note: This type is intentionally `@unchecked Sendable` because `NWPathMonitor` is an Apple type
///   without a `Sendable` conformance. The wrapped monitor is immutable, `pathUpdateHandler` is
///   assigned once before `start(queue:)`, and all lifecycle calls are serialized by the owning
///   ``NetworkConnectivityMonitor``.
internal final class NWPathMonitorEngine: NetworkPathMonitorEngine, @unchecked Sendable {
    private let monitor: NWPathMonitor

    internal init(monitor: NWPathMonitor = NWPathMonitor()) {
        self.monitor = monitor
    }

    internal func start(queue: DispatchQueue, onUpdate: @escaping @Sendable (ConnectivityStatus) -> Void) {
        monitor.pathUpdateHandler = { path in
            onUpdate(Self.map(path.status))
        }
        monitor.start(queue: queue)
    }

    internal func cancel() {
        monitor.cancel()
    }

    /// Maps an `NWPath.Status` onto the SDK's public connectivity status.
    /// - Parameter status: The system network-path status.
    /// - Returns: The corresponding ``ConnectivityStatus``.
    internal static func map(_ status: NWPath.Status) -> ConnectivityStatus {
        status == .satisfied ? .connected : .disconnected
    }
}
