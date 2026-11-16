import Foundation

/// Public contract for observing system network-path connectivity.
///
/// Implementations report the latest known path status and notify registered observers whenever the
/// status transitions, including the initial transition away from
/// ``ConnectivityStatus/unknown``.
///
/// - Note: Status-change callbacks are delivered on the monitor's internal serial queue rather than the
///   main thread. Observers that update UI must dispatch to the main queue themselves. The initial
///   snapshot emitted during observer registration is delivered synchronously on the registering thread.
public protocol ConnectivityMonitorProtocol: Sendable {
    /// The most recently observed connectivity status.
    ///
    /// Defaults to ``ConnectivityStatus/unknown`` until monitoring starts and the first path update is
    /// delivered. When monitoring is stopped, this value retains the last observed status.
    var currentStatus: ConnectivityStatus { get }

    /// Whether connectivity monitoring is currently active.
    var isMonitoring: Bool { get }

    /// Starts monitoring network-path changes.
    ///
    /// Calling this method while monitoring is already active has no effect. Calling it again after
    /// ``stop()`` starts a new monitoring session.
    func start()

    /// Stops monitoring and prevents further observer callbacks.
    ///
    /// Calling this method while monitoring is inactive has no effect.
    func stop()

    /// Registers an observer for connectivity updates.
    ///
    /// The observer is invoked immediately with the current status snapshot on the registering thread.
    /// Subsequent status changes are delivered on the monitor's serial queue.
    /// - Parameter observer: Closure invoked with the current status and every later status change.
    /// - Returns: A token that must be retained to remove the observer later.
    @discardableResult
    func addObserver(_ observer: @escaping @Sendable (ConnectivityStatus) -> Void) -> ConnectivityObservationToken

    /// Removes a previously registered observer.
    /// - Parameter token: The token returned when the observer was registered.
    func removeObserver(_ token: ConnectivityObservationToken)
}
