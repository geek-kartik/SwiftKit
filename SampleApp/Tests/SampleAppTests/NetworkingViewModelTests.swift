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
        viewModel = nil
        mockClient = nil
        mockSession = nil
        mockLogger = nil
        super.tearDown()
    }

    func testGetRequestDecodesJSONResponse() async {
        await viewModel.sendRequest(method: .get, path: "/v1/items")

        XCTAssertEqual(mockClient.callCount, 1)
        XCTAssertEqual(mockClient.sentRequests.first?.method, .get)
        XCTAssertTrue(viewModel.responseText.contains("Mock response"))
        XCTAssertFalse(viewModel.isErrorMessage)
        XCTAssertEqual(viewModel.callHistory.first?.method, .get)
    }

    func testPostRequestEncodesJSONBody() async {
        await viewModel.sendRequest(
            method: .post,
            path: "/v1/items",
            body: "Posted from test"
        )

        let request = mockClient.sentRequests.first
        XCTAssertEqual(request?.method, .post)
        XCTAssertEqual(request?.header(named: "Content-Type"), "application/json")
        XCTAssertEqual(String(data: request?.body ?? Data(), encoding: .utf8), #"{"message":"Posted from test"}"#)
    }

    func testBearerStatusUsesDataMasker() {
        XCTAssertEqual(viewModel.bearerStatus, "Bearer [REDACTED]")
    }

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
