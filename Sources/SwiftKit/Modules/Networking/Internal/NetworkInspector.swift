import Foundation

/// Internal sink used by ``URLSessionNetworkClient`` to publish captured transactions.
internal protocol NetworkTransactionRecording: Sendable {
    /// Records a completed or failed transaction.
    /// - Parameter transaction: The transaction to store.
    func record(_ transaction: NetworkTransaction)
}

/// Thread-safe, bounded transaction store backing ``NetworkInspectorProtocol``.
internal final class NetworkInspector: NetworkInspectorProtocol, NetworkTransactionRecording {
    private struct State {
        var transactions: [NetworkTransaction] = []
        var observers: [UUID: AsyncStream<[NetworkTransaction]>.Continuation] = [:]
    }

    internal let configuration: NetworkInspectorConfiguration
    private let state = ThreadSafeBox<State>(State())

    /// Creates an inspector with the supplied settings.
    /// - Parameter configuration: The capture, retention, and redaction settings.
    internal init(configuration: NetworkInspectorConfiguration) {
        self.configuration = configuration
    }

    internal var transactions: [NetworkTransaction] {
        state.current.transactions
    }

    internal func transaction(id: NetworkTransaction.ID) -> NetworkTransaction? {
        state.current.transactions.first { $0.id == id }
    }

    internal func clear() {
        let snapshot = state.mutate { state -> [NetworkTransaction] in
            state.transactions.removeAll()
            return state.transactions
        }
        broadcast(snapshot)
    }

    internal func updates() -> AsyncStream<[NetworkTransaction]> {
        AsyncStream { continuation in
            let observerID = UUID()

            let snapshot = state.mutate { state -> [NetworkTransaction] in
                state.observers[observerID] = continuation
                return state.transactions
            }

            continuation.yield(snapshot)
            continuation.onTermination = { [weak self] _ in
                self?.state.mutate { $0.observers[observerID] = nil }
            }
        }
    }

    internal func record(_ transaction: NetworkTransaction) {
        guard configuration.isEnabled else { return }

        let stored = transaction.limited(toBodyBytes: configuration.maxBodyBytes)
        let limit = max(1, configuration.maxTransactions)

        let snapshot = state.mutate { state -> [NetworkTransaction] in
            state.transactions.insert(stored, at: 0)
            if state.transactions.count > limit {
                state.transactions.removeLast(state.transactions.count - limit)
            }
            return state.transactions
        }

        broadcast(snapshot)
    }

    /// Delivers a snapshot to every active observer without holding the state lock during yields.
    private func broadcast(_ snapshot: [NetworkTransaction]) {
        for observer in state.current.observers.values {
            observer.yield(snapshot)
        }
    }
}
