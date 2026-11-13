import Foundation

/// Concrete connectivity monitor backed by `NWPathMonitor` through an injectable engine abstraction.
///
/// - Note: This type relies on compiler-checked `Sendable` conformance. All stored properties are
///   immutable and `Sendable`; mutable lifecycle, status, and observer state is confined to
///   ``ThreadSafeBox``, whose locking makes the shared state safe across concurrency domains.
internal final class NetworkConnectivityMonitor: ConnectivityMonitorProtocol {
    private struct State: Sendable {
        var status: ConnectivityStatus = .unknown
        var isMonitoring = false
        var generation: UInt64 = 0
        var engine: NetworkPathMonitorEngine?
        var observers: [ConnectivityObservationToken: @Sendable (ConnectivityStatus) -> Void] = [:]
    }

    private let logger: LoggerProtocol
    private let queue: DispatchQueue
    private let engineFactory: NetworkPathMonitorEngineFactory
    private let state: ThreadSafeBox<State>

    /// Creates a connectivity monitor.
    /// - Parameters:
    ///   - logger: Logger receiving lifecycle and transition diagnostics.
    ///   - queue: Serial queue used for path monitoring and observer callbacks.
    ///   - engineFactory: Factory producing path-monitoring engines.
    internal init(
        logger: LoggerProtocol,
        queue: DispatchQueue = DispatchQueue(label: "com.swiftkit.connectivity.monitor", qos: .utility),
        engineFactory: NetworkPathMonitorEngineFactory = NWPathMonitorEngineFactory()
    ) {
        self.logger = logger
        self.queue = queue
        self.engineFactory = engineFactory
        self.state = ThreadSafeBox(State())
    }

    deinit {
        let engine = state.mutate { state -> NetworkPathMonitorEngine? in
            state.isMonitoring = false
            let currentEngine = state.engine
            state.engine = nil
            return currentEngine
        }
        engine?.cancel()
    }

    internal var currentStatus: ConnectivityStatus {
        state.current.status
    }

    internal var isMonitoring: Bool {
        state.current.isMonitoring
    }

    internal func start() {
        let session = state.mutate { state -> (engine: NetworkPathMonitorEngine, generation: UInt64)? in
            guard !state.isMonitoring else {
                return nil
            }

            state.isMonitoring = true
            state.generation &+= 1

            let engine = engineFactory.makeEngine()
            state.engine = engine
            return (engine, state.generation)
        }

        guard let session else {
            return
        }

        logger.info("Connectivity monitoring started.")

        session.engine.start(queue: queue) { [weak self] status in
            self?.handlePathUpdate(status, generation: session.generation)
        }

        let isSessionActive = state.mutate { state -> Bool in
            state.isMonitoring
                && state.generation == session.generation
                && state.engine === session.engine
        }

        if !isSessionActive {
            session.engine.cancel()
        }
    }

    internal func stop() {
        let engine = state.mutate { state -> NetworkPathMonitorEngine? in
            guard state.isMonitoring else {
                return nil
            }

            state.isMonitoring = false
            state.generation &+= 1

            let currentEngine = state.engine
            state.engine = nil
            return currentEngine
        }

        guard let engine else {
            return
        }

        engine.cancel()
        logger.info("Connectivity monitoring stopped.")
    }

    @discardableResult
    internal func addObserver(
        _ observer: @escaping @Sendable (ConnectivityStatus) -> Void
    ) -> ConnectivityObservationToken {
        let token = ConnectivityObservationToken()
        let snapshot = state.mutate { state -> ConnectivityStatus in
            state.observers[token] = observer
            return state.status
        }

        observer(snapshot)
        return token
    }

    internal func removeObserver(_ token: ConnectivityObservationToken) {
        state.mutate { state in
            state.observers.removeValue(forKey: token)
        }
    }

    /// Applies a path update and notifies observers only when the status actually changed.
    /// - Parameters:
    ///   - status: The newly observed status.
    ///   - generation: The monitoring session that produced the update.
    private func handlePathUpdate(_ status: ConnectivityStatus, generation: UInt64) {
        let observers = state.mutate { state -> [@Sendable (ConnectivityStatus) -> Void]? in
            guard state.isMonitoring,
                  state.generation == generation,
                  state.status != status else {
                return nil
            }

            state.status = status
            return Array(state.observers.values)
        }

        guard let observers else {
            return
        }

        logger.info("Connectivity status changed to \(status.rawValue).")

        for observer in observers {
            observer(status)
        }
    }
}
