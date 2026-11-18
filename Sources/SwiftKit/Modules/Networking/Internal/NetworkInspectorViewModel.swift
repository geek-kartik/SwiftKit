import Combine
import Foundation

/// Observable state for the SDK network inspector screen.
///
/// The view model lives outside the SwiftUI file so filtering and search behavior can be tested
/// on macOS hosts without compiling UIKit.
@MainActor
internal final class NetworkInspectorViewModel: ObservableObject {
    @Published internal private(set) var transactions: [NetworkTransaction]

    internal let configuration: NetworkInspectorConfiguration

    private let inspector: NetworkInspectorProtocol
    private var isObserving = false

    internal init(inspector: NetworkInspectorProtocol) {
        self.inspector = inspector
        self.configuration = inspector.configuration
        self.transactions = inspector.transactions
    }

    /// The number of transactions that completed successfully.
    internal var successCount: Int {
        transactions.filter(\.isSuccess).count
    }

    /// The number of transactions that carry an error.
    internal var failureCount: Int {
        transactions.count - successCount
    }

    /// Returns the visible transactions for the current filter and free-text query.
    ///
    /// The inspector stores transactions newest-first, and filtering preserves that order.
    /// - Parameters:
    ///   - query: Trimmed, case-insensitive text matched against the method, URL, status code,
    ///     error description, and normalized error name.
    ///   - filter: The success/failure filter to apply.
    /// - Returns: Transactions that satisfy both the filter and the query.
    internal func filteredTransactions(
        query: String,
        filter: NetworkTransactionFilter
    ) -> [NetworkTransaction] {
        transactions.filter {
            NetworkTransactionQuery.matches($0, filter: filter, query: query)
        }
    }

    /// Mirrors inspector snapshots into the published array until the calling task is cancelled.
    internal func observe() async {
        guard !isObserving else { return }
        isObserving = true

        for await snapshot in inspector.updates() {
            transactions = snapshot
        }

        isObserving = false
    }

    /// Clears captured history in the inspector and the visible list.
    internal func clear() {
        inspector.clear()
        transactions = inspector.transactions
    }
}

/// The status filter shown by the network inspector.
internal enum NetworkTransactionFilter: String, CaseIterable, Identifiable {
    case all
    case succeeded
    case failed

    internal var id: String { rawValue }

    internal var title: String {
        switch self {
        case .all: return "All"
        case .succeeded: return "Succeeded"
        case .failed: return "Failed"
        }
    }

    /// Whether the transaction passes this filter.
    /// - Parameter transaction: The transaction to inspect.
    /// - Returns: `true` when the transaction should be visible.
    internal func matches(_ transaction: NetworkTransaction) -> Bool {
        switch self {
        case .all: return true
        case .succeeded: return transaction.isSuccess
        case .failed: return !transaction.isSuccess
        }
    }
}

/// Free-text matching rules for the network inspector search field.
internal enum NetworkTransactionQuery {
    /// Whether a transaction matches the filter and query.
    /// - Parameters:
    ///   - transaction: The transaction to inspect.
    ///   - filter: The success/failure filter to apply.
    ///   - query: Text matched case-insensitively against the method, URL, status code, error
    ///     description, and normalized error name. Whitespace is ignored at both ends.
    /// - Returns: `true` when the transaction should be visible.
    internal static func matches(
        _ transaction: NetworkTransaction,
        filter: NetworkTransactionFilter,
        query: String
    ) -> Bool {
        guard filter.matches(transaction) else { return false }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return true }

        let haystack = [
            transaction.request.method.rawValue,
            transaction.request.url.absoluteString,
            transaction.statusCode.map(String.init) ?? "",
            transaction.errorDescription ?? "",
            transaction.error?.logDescription ?? ""
        ]
        .joined(separator: " ")
        .lowercased()

        return haystack.contains(trimmed)
    }
}
