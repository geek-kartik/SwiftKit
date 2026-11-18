import Foundation

internal actor RefreshCoordinator {
    private var inFlight: Task<Void, Error>?

    internal func refresh(using action: @escaping @Sendable () async throws -> Void) async throws {
        if let inFlight {
            try await inFlight.value
            return
        }
        let task = Task { try await action() }
        inFlight = task
        defer { inFlight = nil }
        try await task.value
    }
}
