import XCTest
@testable import SwiftKit

/// Tests for the network inspector's filtering, search, counts, and live updates.
@MainActor
final class NetworkInspectorViewModelTests: XCTestCase {
    // MARK: - Snapshot

    func testInitialSnapshotMirrorsInspectorHistory() {
        let inspector = makeInspector()
        let recorded = recordFixtures(in: inspector)
        let model = NetworkInspectorViewModel(inspector: inspector)

        XCTAssertEqual(model.transactions.map(\.id), recorded.map(\.id))
    }

    func testConfigurationMirrorsInspector() {
        let configuration = NetworkInspectorConfiguration(
            isEnabled: true,
            maxTransactions: 7,
            maxBodyBytes: 1_024,
            sensitiveDataPolicy: .include
        )
        let inspector = NetworkInspector(configuration: configuration)
        let model = NetworkInspectorViewModel(inspector: inspector)

        XCTAssertEqual(model.configuration.maxTransactions, 7)
        XCTAssertEqual(model.configuration.maxBodyBytes, 1_024)
        XCTAssertEqual(model.configuration.sensitiveDataPolicy, .include)
    }

    func testSuccessAndFailureCounts() {
        let inspector = makeInspector()
        recordFixtures(in: inspector)

        let model = NetworkInspectorViewModel(inspector: inspector)

        XCTAssertEqual(model.transactions.count, 4)
        XCTAssertEqual(model.successCount, 2)
        XCTAssertEqual(model.failureCount, 2)
    }

    // MARK: - Filtering

    func testAllFilterKeepsNewestFirst() {
        let inspector = makeInspector()
        let recorded = recordFixtures(in: inspector)
        let model = NetworkInspectorViewModel(inspector: inspector)

        let visible = model.filteredTransactions(query: "", filter: .all)

        XCTAssertEqual(visible.map(\.id), recorded.map(\.id))
    }

    func testSucceededFilterKeepsOnlySuccessfulTransactions() {
        let inspector = makeInspector()
        recordFixtures(in: inspector)
        let model = NetworkInspectorViewModel(inspector: inspector)

        let visible = model.filteredTransactions(query: "", filter: .succeeded)

        XCTAssertEqual(visible.map(\.request.method), [.get, .get])
        XCTAssertTrue(visible.allSatisfy(\.isSuccess))
    }

    func testFailedFilterKeepsOnlyFailedTransactions() {
        let inspector = makeInspector()
        recordFixtures(in: inspector)
        let model = NetworkInspectorViewModel(inspector: inspector)

        let visible = model.filteredTransactions(query: "", filter: .failed)

        XCTAssertEqual(visible.map(\.request.method), [.delete, .post])
        XCTAssertTrue(visible.allSatisfy { !$0.isSuccess })
    }

    func testFilterTitlesAndOrder() {
        XCTAssertEqual(
            NetworkTransactionFilter.allCases.map(\.title),
            ["All", "Succeeded", "Failed"]
        )
    }

    // MARK: - Search

    func testSearchMatchesHTTPMethod() {
        let model = makeModel()

        let visible = model.filteredTransactions(query: "post", filter: .all)

        XCTAssertEqual(visible.map(\.pathText), ["/v1/transfers"])
    }

    func testSearchMatchesURLPath() {
        let model = makeModel()

        let visible = model.filteredTransactions(query: "acc-1", filter: .all)

        XCTAssertEqual(visible.map(\.pathText), ["/v1/accounts/acc-1/transactions?page=2"])
    }

    func testSearchMatchesStatusCode() {
        let model = makeModel()

        let visible = model.filteredTransactions(query: "500", filter: .all)

        XCTAssertEqual(visible.map(\.pathText), ["/v1/transfers"])
    }

    func testSearchMatchesNormalizedErrorName() {
        let model = makeModel()

        let visible = model.filteredTransactions(query: "timeout", filter: .all)

        XCTAssertEqual(visible.map(\.pathText), ["/v1/alerts"])
    }

    func testSearchMatchesErrorDescription() {
        let model = makeModel()

        let visible = model.filteredTransactions(query: "timed out", filter: .all)

        XCTAssertEqual(visible.map(\.pathText), ["/v1/alerts"])
    }

    func testSearchIsCaseInsensitiveAndTrimsWhitespace() {
        let model = makeModel()

        let visible = model.filteredTransactions(query: "  GeT  ", filter: .all)

        XCTAssertEqual(visible.count, 2)
        XCTAssertTrue(visible.allSatisfy { $0.request.method == .get })
    }

    func testBlankQueryKeepsEveryTransactionInTheFilter() {
        let model = makeModel()

        XCTAssertEqual(model.filteredTransactions(query: "   ", filter: .all).count, 4)
        XCTAssertEqual(model.filteredTransactions(query: "\n", filter: .failed).count, 2)
    }

    func testSearchCombinesWithFilter() {
        let model = makeModel()

        let succeeded = model.filteredTransactions(query: "accounts", filter: .succeeded)
        let failed = model.filteredTransactions(query: "accounts", filter: .failed)

        XCTAssertEqual(succeeded.count, 2)
        XCTAssertTrue(failed.isEmpty)
    }

    func testUnknownQueryReturnsNoMatches() {
        let model = makeModel()

        XCTAssertTrue(model.filteredTransactions(query: "definitely-not-here", filter: .all).isEmpty)
    }

    // MARK: - Clear and updates

    func testClearRemovesVisibleAndStoredTransactions() {
        let inspector = makeInspector()
        recordFixtures(in: inspector)
        let model = NetworkInspectorViewModel(inspector: inspector)

        model.clear()

        XCTAssertTrue(model.transactions.isEmpty)
        XCTAssertTrue(inspector.transactions.isEmpty)
        XCTAssertEqual(model.successCount, 0)
        XCTAssertEqual(model.failureCount, 0)
    }

    func testObservationReceivesNewTransactions() async throws {
        let inspector = makeInspector()
        let model = NetworkInspectorViewModel(inspector: inspector)

        let observation = Task { await model.observe() }
        defer { observation.cancel() }

        inspector.record(makeTransaction(method: .patch, path: "/v1/accounts/acc-1"))

        let deadline = Date().addingTimeInterval(1)
        while model.transactions.isEmpty && Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(model.transactions.map(\.pathText), ["/v1/accounts/acc-1"])
        XCTAssertEqual(model.successCount, 1)
        XCTAssertEqual(model.failureCount, 0)
    }

    // MARK: - Helpers

    private func makeModel() -> NetworkInspectorViewModel {
        let inspector = makeInspector()
        recordFixtures(in: inspector)
        return NetworkInspectorViewModel(inspector: inspector)
    }

    private func makeInspector() -> NetworkInspector {
        NetworkInspector(
            configuration: NetworkInspectorConfiguration(isEnabled: true)
        )
    }

    /// Records four transactions and returns them in newest-first order.
    @discardableResult
    private func recordFixtures(in inspector: NetworkInspector) -> [NetworkTransaction] {
        let accounts = makeTransaction(method: .get, path: "/v1/accounts")
        let transfer = makeTransaction(
            method: .post,
            path: "/v1/transfers",
            error: .httpStatus(NetworkResponse(statusCode: 500, data: Data()))
        )
        let history = makeTransaction(
            method: .get,
            path: "/v1/accounts/acc-1/transactions?page=2"
        )
        let alerts = makeTransaction(method: .delete, path: "/v1/alerts", error: .timeout)

        [accounts, transfer, history, alerts].forEach(inspector.record)

        return [alerts, history, transfer, accounts]
    }

    private func makeTransaction(
        method: HTTPMethod,
        path: String,
        error: NetworkError? = nil
    ) -> NetworkTransaction {
        let url = URL(string: "https://api.example.com\(path)")!

        return NetworkTransaction(
            startedAt: Date(),
            duration: 0.05,
            request: NetworkTransaction.Request(method: method, url: url),
            response: error == nil
                ? NetworkTransaction.Response(statusCode: 200, body: .init(data: Data()))
                : nil,
            error: error
        )
    }
}
