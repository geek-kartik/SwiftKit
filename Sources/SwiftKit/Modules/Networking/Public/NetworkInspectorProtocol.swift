import Foundation

/// Public read-only contract for the SDK's session network inspector.
///
/// The inspector captures transactions at the networking layer after the request has been fully
/// resolved, so recorded URLs, headers, and bodies match what was sent on the wire. It is disabled
/// by default; enable it through ``NetworkInspectorConfiguration/isEnabled`` in
/// ``NetworkConfiguration/inspector``.
///
/// All members are safe to call from any concurrency domain. ``updates()`` delivers a live
/// snapshot stream for UI binding.
public protocol NetworkInspectorProtocol: Sendable {
    /// The active inspector settings, including the sensitive-data policy.
    var configuration: NetworkInspectorConfiguration { get }

    /// The captured session transactions, newest first.
    var transactions: [NetworkTransaction] { get }

    /// Returns a captured transaction by identifier.
    /// - Parameter id: The transaction identifier.
    /// - Returns: The matching transaction, or `nil` when it has been evicted or cleared.
    func transaction(id: NetworkTransaction.ID) -> NetworkTransaction?

    /// Removes every captured transaction.
    func clear()

    /// Streams the current snapshot followed by every subsequent change.
    ///
    /// Each iteration yields the full history, newest first. The stream ends when the caller's
    /// task is cancelled and does not buffer snapshots.
    /// - Returns: An async stream of transaction snapshots.
    func updates() -> AsyncStream<[NetworkTransaction]>
}
