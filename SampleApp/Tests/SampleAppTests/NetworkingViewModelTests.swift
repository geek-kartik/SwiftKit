import XCTest
import SwiftKit
@testable import SampleApp

private final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }

    var current: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

/// Suspends a mock request until the test opens the gate.
private actor RequestGate {
    private var started = false
    private var opened = false
    private var arrivals = 0
    private var arrivalTarget = 0
    private var startContinuation: CheckedContinuation<Void, Never>?
    private var arrivalContinuation: CheckedContinuation<Void, Never>?
    private var waitContinuations: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        arrivals += 1
        if arrivalTarget > 0, arrivals >= arrivalTarget {
            arrivalContinuation?.resume()
            arrivalContinuation = nil
        }

        if !started {
            started = true
            startContinuation?.resume()
            startContinuation = nil
        }
        guard !opened else { return }
        await withCheckedContinuation { waitContinuations.append($0) }
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { startContinuation = $0 }
    }

    func waitForRequests(_ count: Int) async {
        arrivalTarget = count
        guard arrivals < count else { return }
        await withCheckedContinuation { arrivalContinuation = $0 }
    }

    func open() {
        opened = true
        let continuations = waitContinuations
        waitContinuations.removeAll()
        continuations.forEach { $0.resume() }
    }
}

@MainActor
final class NetworkingViewModelTests: XCTestCase {
    private var mockClient: MockNetworkClient!
    private var mockSession: MockSessionManager!
    private var mockLogger: MockLogger!
    private var viewModel: NetworkingViewModel!

    override func setUp() {
        super.setUp()
        Self.ensureSDKInitialized()
        mockSession = MockSessionManager()
        try? mockSession.startSession(
            Session(
                accessToken: "test_access_token",
                refreshToken: "test_refresh_token",
                expiresAt: Date().addingTimeInterval(3600),
                userID: "network-user"
            )
        )
        mockClient = MockNetworkClient()
        mockLogger = MockLogger()
        viewModel = NetworkingViewModel(
            networkClient: mockClient,
            session: mockSession,
            logger: mockLogger
        )
    }

    override func tearDown() {
        viewModel.cleanup()
        viewModel = nil
        mockClient = nil
        mockSession = nil
        mockLogger = nil
        super.tearDown()
    }

    // MARK: - Core request behavior

    func testGetRequestDecodesJSONResponse() async {
        await viewModel.sendRequest(method: .get, path: "/v1/items")

        XCTAssertEqual(mockClient.callCount, 1)
        XCTAssertEqual(mockClient.sentRequests.first?.method, .get)
        XCTAssertTrue(viewModel.responseText.contains("Mock response"))
        XCTAssertFalse(viewModel.isErrorMessage)
        XCTAssertEqual(viewModel.callHistory.first?.method, .get)
        XCTAssertEqual(viewModel.callHistory.first?.statusCode, 200)
        XCTAssertEqual(viewModel.lastResponse?.statusCode, 200)
        XCTAssertEqual(viewModel.lastResponse?.byteCount, MockNetworkClient.successResponse().data.count)
        XCTAssertEqual(viewModel.inFlightCount, 0)
    }

    func testPostRequestSendsRawJSONBodyUnchanged() async {
        let json = #"{"message":"Posted from test","count":2}"#

        await viewModel.sendRequest(method: .post, path: "/v1/items", body: json)

        let request = mockClient.sentRequests.first
        XCTAssertEqual(request?.method, .post)
        XCTAssertEqual(request?.header(named: "Content-Type"), "application/json")
        XCTAssertEqual(request?.body, Data(json.utf8))
    }

    func testInvalidJSONBodyFailsBeforeNetworkCall() async {
        await viewModel.sendRequest(method: .post, path: "/v1/items", body: "not json")

        XCTAssertEqual(mockClient.callCount, 0)
        XCTAssertTrue(viewModel.isErrorMessage)
        XCTAssertTrue(viewModel.statusMessage.lowercased().contains("json"))
        XCTAssertEqual(viewModel.inFlightCount, 0)
    }

    func testHeadersTimeoutAndCachePolicyAreApplied() async {
        viewModel.headersText = "X-Custom: value\nX-Second: two"
        viewModel.timeoutText = "12.5"
        viewModel.cachePolicy = .returnCacheDataElseLoad

        await viewModel.sendRequest(method: .get, path: "/v1/items")

        let request = mockClient.sentRequests.first
        XCTAssertEqual(request?.header(named: "X-Custom"), "value")
        XCTAssertEqual(request?.header(named: "X-Second"), "two")
        XCTAssertEqual(request?.timeoutInterval, 12.5)
        XCTAssertEqual(request?.cachePolicy, .returnCacheDataElseLoad)
    }

    func testInvalidHeaderAndTimeoutFailBeforeNetworkCall() async {
        viewModel.headersText = "missing separator"
        await viewModel.sendRequest(method: .get, path: "/v1/items")
        XCTAssertEqual(mockClient.callCount, 0)
        XCTAssertTrue(viewModel.statusMessage.contains("Invalid header line"))

        viewModel.headersText = ""
        viewModel.timeoutText = "zero"
        await viewModel.sendRequest(method: .get, path: "/v1/items")
        XCTAssertEqual(mockClient.callCount, 0)
        XCTAssertTrue(viewModel.statusMessage.contains("positive number"))
    }

    func testBearerStatusUsesDataMasker() {
        XCTAssertEqual(viewModel.bearerStatus, "Bearer [REDACTED]")
    }

    // MARK: - Task tracking and duplicate suppression

    func testDuplicateInFlightRequestIsSuppressed() async {
        let gate = RequestGate()
        let client = MockNetworkClient { _ in
            await gate.wait()
            return MockNetworkClient.successResponse()
        }
        viewModel = NetworkingViewModel(networkClient: client, session: mockSession, logger: mockLogger)

        let first = Task { await viewModel.sendRequest(method: .get, path: "/v1/items") }
        await gate.waitUntilStarted()

        await viewModel.sendRequest(method: .get, path: "/v1/items")

        XCTAssertEqual(client.callCount, 1)
        XCTAssertEqual(viewModel.inFlightCount, 1)
        XCTAssertEqual(viewModel.suppressedDuplicateCount, 1)
        XCTAssertTrue(viewModel.statusMessage.contains("already in flight"))

        await gate.open()
        await first.value

        XCTAssertEqual(viewModel.inFlightCount, 0)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testDifferentRequestsMayRunConcurrently() async {
        let gate = RequestGate()
        let client = MockNetworkClient { _ in
            await gate.wait()
            return MockNetworkClient.successResponse()
        }
        viewModel = NetworkingViewModel(networkClient: client, session: mockSession, logger: mockLogger)

        let first = Task { await viewModel.sendRequest(method: .get, path: "/v1/first") }
        await gate.waitUntilStarted()
        let second = Task { await viewModel.sendRequest(method: .get, path: "/v1/second") }

        await gate.waitForRequests(2)

        XCTAssertEqual(client.callCount, 2)
        XCTAssertEqual(viewModel.inFlightCount, 2)
        XCTAssertEqual(viewModel.suppressedDuplicateCount, 0)

        await gate.open()
        await first.value
        await second.value
        XCTAssertEqual(viewModel.inFlightCount, 0)
    }

    func testCancelActiveRequestStopsInFlightWork() async {
        let gate = RequestGate()
        let client = MockNetworkClient { _ in
            await gate.wait()
            try Task.checkCancellation()
            return MockNetworkClient.successResponse()
        }
        viewModel = NetworkingViewModel(networkClient: client, session: mockSession, logger: mockLogger)

        let task = Task { await viewModel.sendRequest(method: .get, path: "/v1/items") }
        await gate.waitUntilStarted()
        XCTAssertEqual(viewModel.inFlightCount, 1)

        viewModel.cancelActiveRequest()
        await gate.open()
        await task.value

        XCTAssertEqual(viewModel.inFlightCount, 0)
        XCTAssertEqual(viewModel.statusMessage, "Request cancelled.")
        XCTAssertEqual(viewModel.callHistory.first?.isError, false)
    }

    func testCleanupRemovesSessionObserver() {
        XCTAssertEqual(mockSession.observerCount, 1)

        viewModel.cleanup()

        XCTAssertEqual(mockSession.observerCount, 0)

        viewModel.activate()

        XCTAssertEqual(mockSession.observerCount, 1)
    }

    func testSessionLogoutCancelsInFlightRequest() async {
        let gate = RequestGate()
        let client = MockNetworkClient { _ in
            await gate.wait()
            try Task.checkCancellation()
            return MockNetworkClient.successResponse()
        }
        viewModel = NetworkingViewModel(networkClient: client, session: mockSession, logger: mockLogger)

        let task = Task { await viewModel.sendRequest(method: .get, path: "/v1/items") }
        await gate.waitUntilStarted()

        try? mockSession.logout()
        for _ in 0..<100 where viewModel.bearerStatus != "No active bearer token" {
            await Task.yield()
        }

        await gate.open()
        await task.value

        XCTAssertEqual(viewModel.inFlightCount, 0)
        XCTAssertEqual(viewModel.statusMessage, "Session ended; the in-flight request was cancelled.")
    }

    // MARK: - 401 handling

    func testUnauthorizedResponseRefreshesSessionAndRetriesOnce() async {
        let counter = CallCounter()
        let client = MockNetworkClient { _ in
            if counter.next() == 1 {
                throw NetworkError.httpStatus(
                    NetworkResponse(statusCode: 401, data: Data(#"{"error":"expired"}"#.utf8))
                )
            }
            return MockNetworkClient.successResponse()
        }
        viewModel = NetworkingViewModel(networkClient: client, session: mockSession, logger: mockLogger)

        await viewModel.sendRequest(method: .get, path: "/v1/protected")

        XCTAssertEqual(counter.current, 2)
        XCTAssertEqual(client.callCount, 2)
        XCTAssertEqual(mockSession.asyncRefreshCallCount, 1)
        XCTAssertTrue(viewModel.didRetryAfter401)
        XCTAssertFalse(viewModel.isErrorMessage)
        XCTAssertTrue(viewModel.responseText.contains("Mock response"))
    }

    func testUnauthorizedAfterLogoutDoesNotRefreshOrRetry() async {
        try? mockSession.logout()
        let client = MockNetworkClient { _ in
            throw NetworkError.httpStatus(NetworkResponse(statusCode: 401, data: Data()))
        }
        viewModel = NetworkingViewModel(networkClient: client, session: mockSession, logger: mockLogger)

        await viewModel.sendRequest(method: .get, path: "/v1/protected")

        XCTAssertEqual(client.callCount, 1)
        XCTAssertEqual(mockSession.asyncRefreshCallCount, 0)
        XCTAssertEqual(mockSession.handleUnauthorizedCallCount, 0)
        XCTAssertFalse(viewModel.didRetryAfter401)
        XCTAssertTrue(viewModel.statusMessage.contains("skipped"))
    }

    func testSecondUnauthorizedAfterRefreshClearsSession() async {
        let client = MockNetworkClient { _ in
            throw NetworkError.httpStatus(NetworkResponse(statusCode: 401, data: Data()))
        }
        viewModel = NetworkingViewModel(networkClient: client, session: mockSession, logger: mockLogger)

        await viewModel.sendRequest(method: .get, path: "/v1/protected")

        XCTAssertEqual(client.callCount, 2)
        XCTAssertEqual(mockSession.asyncRefreshCallCount, 1)
        XCTAssertEqual(mockSession.handleUnauthorizedCallCount, 1)
        XCTAssertTrue(viewModel.isErrorMessage)
        XCTAssertTrue(viewModel.statusMessage.contains("Second HTTP 401"))
        XCTAssertEqual(viewModel.bearerStatus, "No active bearer token")
    }

    func testConcurrentUnauthorizedRequestsShareSingleRefresh() async {
        mockSession.asyncRefreshDelay = 0.3
        let counter = CallCounter()
        let client = MockNetworkClient { _ in
            if counter.next() <= 2 {
                throw NetworkError.httpStatus(NetworkResponse(statusCode: 401, data: Data()))
            }
            return MockNetworkClient.successResponse()
        }
        viewModel = NetworkingViewModel(networkClient: client, session: mockSession, logger: mockLogger)

        async let first: Void = viewModel.sendRequest(method: .get, path: "/v1/first")
        async let second: Void = viewModel.sendRequest(method: .get, path: "/v1/second")
        _ = await (first, second)

        XCTAssertEqual(client.callCount, 4)
        XCTAssertEqual(mockSession.asyncRefreshCallCount, 1)
        XCTAssertEqual(viewModel.inFlightCount, 0)
    }

    func testRefreshFailureClearsSessionAndReportsError() async {
        let client = MockNetworkClient { _ in
            throw NetworkError.httpStatus(NetworkResponse(statusCode: 401, data: Data()))
        }
        mockSession.asyncRefreshError = SessionError.refreshFailed
        viewModel = NetworkingViewModel(networkClient: client, session: mockSession, logger: mockLogger)

        await viewModel.sendRequest(method: .get, path: "/v1/protected")

        XCTAssertEqual(mockSession.asyncRefreshCallCount, 1)
        XCTAssertEqual(mockSession.handleUnauthorizedCallCount, 1)
        XCTAssertTrue(viewModel.isErrorMessage)
        XCTAssertTrue(viewModel.statusMessage.contains("session was cleared"))
        XCTAssertEqual(viewModel.bearerStatus, "No active bearer token")
    }

    // MARK: - Error presentation

    func testNonAuthenticationErrorDoesNotRefreshOrRetry() async {
        let counter = CallCounter()
        let client = MockNetworkClient { _ in
            _ = counter.next()
            throw NetworkError.httpStatus(
                NetworkResponse(statusCode: 500, data: Data("failure".utf8))
            )
        }
        viewModel = NetworkingViewModel(networkClient: client, session: mockSession, logger: mockLogger)

        await viewModel.sendRequest(method: .get, path: "/v1/failure")

        XCTAssertEqual(counter.current, 1)
        XCTAssertEqual(client.callCount, 1)
        XCTAssertEqual(mockSession.asyncRefreshCallCount, 0)
        XCTAssertTrue(viewModel.isErrorMessage)
        XCTAssertTrue(viewModel.statusMessage.contains("500"))
    }

    func testDecodingFailureIsReported() async {
        let client = MockNetworkClient { _ in
            MockNetworkClient.successResponse(data: Data("not json".utf8))
        }
        viewModel = NetworkingViewModel(networkClient: client, session: mockSession, logger: mockLogger)

        await viewModel.sendRequest(method: .get, path: "/v1/bad-json")

        XCTAssertTrue(viewModel.isErrorMessage)
        XCTAssertTrue(viewModel.statusMessage.lowercased().contains("decode"))
    }

    func testClearHistoryRemovesCallsAndCallbacks() async {
        await viewModel.sendRequest(method: .get, path: "/v1/items")
        viewModel.clearHistory()

        XCTAssertTrue(viewModel.callHistory.isEmpty)
        XCTAssertTrue(viewModel.callbackEvents.isEmpty)
    }

    func testErrorRecordUsesAttemptedMethodAndPath() async {
        let client = MockNetworkClient { _ in
            throw NetworkError.httpStatus(
                NetworkResponse(
                    statusCode: 500,
                    headers: ["Content-Type": "application/json"],
                    data: Data(#"{"status":"error","message":"Simulated server failure."}"#.utf8)
                )
            )
        }
        viewModel = NetworkingViewModel(networkClient: client, session: mockSession, logger: mockLogger)
        viewModel.selectedMethod = .get
        viewModel.path = "/v1/items"

        await viewModel.sendRequest(method: .post, path: "/v1/failure", body: #"{"message":"ignored"}"#)

        let record = viewModel.callHistory.first
        XCTAssertEqual(record?.method, .post)
        XCTAssertEqual(record?.path, "/v1/failure")
        XCTAssertEqual(record?.statusCode, 500)
        XCTAssertTrue(record?.isError == true)
        XCTAssertTrue(viewModel.statusMessage.contains("Simulated server failure."))
        XCTAssertEqual(viewModel.lastResponse?.statusCode, 500)
    }

    func testDiagnosticsToggleControlsLoggerOutput() async {
        await viewModel.sendRequest(method: .get, path: "/v1/items")
        XCTAssertTrue(mockLogger.loggedMessages.contains { $0.message.contains("GET /v1/items") })
        let loggedBefore = mockLogger.loggedMessages.count

        viewModel.logsDiagnostics = false
        await viewModel.sendRequest(method: .get, path: "/v1/items")

        XCTAssertEqual(mockLogger.loggedMessages.count, loggedBefore)
    }

    // MARK: - Demo session

    func testStartDemoSessionAddsBearerToken() {
        try? mockSession.logout()
        viewModel.refreshState()
        XCTAssertEqual(viewModel.bearerStatus, "No active bearer token")

        viewModel.startDemoSession()

        XCTAssertEqual(mockSession.startSessionCallCount, 2)
        XCTAssertEqual(viewModel.bearerStatus, "Bearer [REDACTED]")
        XCTAssertTrue(viewModel.statusMessage.contains("Demo session started"))
    }

    func testDemoSessionUsesGeneratedTokensAndFutureExpiry() {
        viewModel.startDemoSession()
        let first = mockSession.currentSession

        XCTAssertNotNil(first)
        XCTAssertTrue(first?.accessToken.hasPrefix("sample_access_") == true)
        XCTAssertTrue(first?.refreshToken?.hasPrefix("sample_refresh_") == true)
        XCTAssertNotEqual(first?.accessToken, "sample_access_token_abc123")
        XCTAssertTrue((first?.expiresAt ?? .distantPast) > Date())

        try? mockSession.logout()
        viewModel.startDemoSession()
        let second = mockSession.currentSession

        XCTAssertNotNil(second)
        XCTAssertNotEqual(first?.accessToken, second?.accessToken)
        XCTAssertNotEqual(first?.refreshToken, second?.refreshToken)
    }

    func testExpiredSessionBlocksSendingUntilSignIn() async {
        try? mockSession.logout()
        try? mockSession.startSession(
            Session(
                accessToken: "expired_access",
                refreshToken: "expired_refresh",
                expiresAt: Date().addingTimeInterval(-60),
                userID: "expired-user"
            )
        )
        viewModel = NetworkingViewModel(networkClient: mockClient, session: mockSession, logger: mockLogger)

        await viewModel.sendRequest(method: .get, path: "/v1/items")

        XCTAssertEqual(mockClient.callCount, 0)
        XCTAssertTrue(viewModel.isErrorMessage)
        XCTAssertTrue(viewModel.statusMessage.contains("expired"))
        XCTAssertEqual(viewModel.inFlightCount, 0)
    }

    private static func ensureSDKInitialized() {
        guard !SwiftKit.isInitialized else { return }
        let configuration = SwiftKitConfiguration(
            subsystem: "com.swiftkit.sampleapp.tests",
            category: "NetworkingViewModelTests",
            keychainService: "com.swiftkit.sampleapp.tests.storage"
        )
        try? SwiftKit.initialize(configuration: configuration)
    }
}
