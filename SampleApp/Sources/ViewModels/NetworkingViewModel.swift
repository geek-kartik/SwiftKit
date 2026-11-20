import Foundation
import SwiftUI
import SwiftKit

public struct NetworkingCallRecord: Identifiable, Sendable {
    public let id = UUID()
    public let timestamp: Date
    public let method: HTTPMethod
    public let path: String
    public let detail: String
    public let statusCode: Int?
    public let isError: Bool

    public init(
        method: HTTPMethod,
        path: String,
        detail: String,
        statusCode: Int? = nil,
        isError: Bool,
        timestamp: Date = Date()
    ) {
        self.method = method
        self.path = path
        self.detail = detail
        self.statusCode = statusCode
        self.isError = isError
        self.timestamp = timestamp
    }
}

/// Metadata surfaced from the raw `NetworkResponse` returned by the SDK.
public struct NetworkingResponseSummary: Sendable, Equatable {
    public let statusCode: Int
    public let contentType: String?
    public let byteCount: Int
    public let elapsedMilliseconds: Int
    public let url: URL?

    public init(
        statusCode: Int,
        contentType: String?,
        byteCount: Int,
        elapsedMilliseconds: Int,
        url: URL?
    ) {
        self.statusCode = statusCode
        self.contentType = contentType
        self.byteCount = byteCount
        self.elapsedMilliseconds = elapsedMilliseconds
        self.url = url
    }
}

@MainActor
public final class NetworkingViewModel: ObservableObject {
    @Published public var selectedMethod: HTTPMethod = .get
    @Published public var path = "/v1/items"
    @Published public var bodyText = #"{"message":"Hello from SampleApp"}"#
    @Published public var responseText = ""
    @Published public var statusMessage = ""
    @Published public var isErrorMessage = false
    @Published public var isLoading = false
    @Published public var didRetryAfter401 = false
    @Published public var bearerStatus = "No active bearer token"
    @Published public var callHistory: [NetworkingCallRecord] = []
    @Published public var callbackEvents: [String] = []
    @Published public var lastResponse: NetworkingResponseSummary?

    /// Controls whether this screen writes request results to the SDK logger.
    ///
    /// This is an app-level switch that demonstrates developer-controlled diagnostics:
    /// turn it off to keep request details out of OSLog when sharing a build.
    @Published public var logsDiagnostics = true

    private let networkClient: NetworkClientProtocol
    private let session: SessionManagerProtocol
    private let logger: LoggerProtocol
    private var callbackObserver: NSObjectProtocol?
    private var authObserver: NSObjectProtocol?
    private var requestStartedAt: Date?

    public init(
        networkClient: NetworkClientProtocol? = nil,
        session: SessionManagerProtocol? = nil,
        logger: LoggerProtocol? = nil
    ) {
        self.networkClient = networkClient ?? SDKService.shared.networkClient
        self.session = session ?? SDKService.shared.session
        self.logger = logger ?? SDKService.shared.logger
        startListeningForCallbacks()
        refreshState()
    }

    deinit {
        if let callbackObserver {
            NotificationCenter.default.removeObserver(callbackObserver)
        }
        if let authObserver {
            NotificationCenter.default.removeObserver(authObserver)
        }
    }

    public func send() async {
        await sendRequest(method: selectedMethod, path: path, body: bodyText)
    }

    public func sendRequest(method: HTTPMethod, path: String, body: String? = nil) async {
        isLoading = true
        didRetryAfter401 = false
        lastResponse = nil
        requestStartedAt = Date()
        defer { isLoading = false }

        do {
            try await execute(method: method, path: path, body: body, allowRetry: true)
        } catch {
            present(error, method: method, path: path)
        }

        refreshBearerStatus()
    }

    /// Sends the protected request after invalidating the sample backend token so the
    /// `401 → refresh → retry` flow can be demonstrated repeatedly.
    public func sendProtectedRequest() async {
        guard session.currentSession != nil else {
            setStatus("Start a demo session first, then run the 401 scenario.", isError: true)
            return
        }
        await SampleBackend.shared.markTokenStale()
        await sendRequest(method: .get, path: "/v1/protected")
    }

    /// Starts an in-memory demo session so the token provider has a bearer token to inject.
    public func startDemoSession() {
        let demo = Session(
            accessToken: "sample_access_token_abc123",
            refreshToken: "sample_refresh_token_xyz789",
            expiresAt: Date().addingTimeInterval(3600),
            userID: "network-user-42"
        )

        do {
            try session.startSession(demo)
            refreshState()
            setStatus("Demo session started. Requests now include an Authorization header.", isError: false)
        } catch {
            setStatus("Could not start a demo session: \(error.localizedDescription)", isError: true)
        }
    }

    public func clearHistory() {
        callHistory.removeAll()
        callbackEvents.removeAll()
    }

    /// Refreshes derived state when the screen appears, since the Session tab may have
    /// started or cleared the session while this screen was off-screen.
    public func refreshState() {
        refreshBearerStatus()
    }

    private func execute(
        method: HTTPMethod,
        path: String,
        body: String?,
        allowRetry: Bool
    ) async throws {
        let request = try makeRequest(method: method, path: path, body: body)
        let startedAt = Date()

        do {
            let response = try await networkClient.send(request)
            let elapsed = elapsedMilliseconds(since: startedAt)

            lastResponse = NetworkingResponseSummary(
                statusCode: response.statusCode,
                contentType: response.header(named: "Content-Type"),
                byteCount: response.data.count,
                elapsedMilliseconds: elapsed,
                url: response.url
            )
            responseText = Self.prettyJSON(from: response.data)

            let summary: String
            if method == .delete {
                summary = "\(response.data.count) B raw body"
            } else {
                let decoded = try response.decode(
                    SampleAPIResponse.self,
                    using: networkClient.configuration.decoderFactory()
                )
                summary = "\(decoded.status): \(decoded.message)"
            }

            let detail = "HTTP \(response.statusCode) · \(summary)"
            record(method: method, path: path, detail: detail, statusCode: response.statusCode, isError: false)
            setStatus("\(method.rawValue) \(path) completed in \(elapsed) ms.", isError: false)
        } catch let error as NetworkError where error.statusCode == 401 && allowRetry {
            didRetryAfter401 = true
            record(
                method: method,
                path: path,
                detail: "HTTP 401 · refreshing the session before one retry",
                statusCode: 401,
                isError: true
            )
            setStatus("Received 401. Refreshing the session and retrying once…", isError: false)

            let refreshed: Session
            do {
                refreshed = try await session.refreshSession()
            } catch {
                session.handleUnauthorized()
                refreshBearerStatus()
                let message = "Token refresh failed; the session was cleared. \(error.localizedDescription)"
                setStatus(message, isError: true)
                record(method: method, path: path, detail: message, statusCode: 401, isError: true)
                return
            }

            refreshBearerStatus()
            setStatus("Refreshed \(refreshed.userID ?? "the session"). Retrying request…", isError: false)
            try await execute(method: method, path: path, body: body, allowRetry: false)
        }
    }

    private func makeRequest(method: HTTPMethod, path: String, body: String?) throws -> NetworkRequest {
        var request = try NetworkRequest(path: path, method: method)

        if method != .get, let body, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request = try request.withJSONBody(SampleJSONBody(message: body))
        }

        return request
    }

    private func present(_ error: Error, method: HTTPMethod, path: String) {
        guard let networkError = error as? NetworkError else {
            let message = "Request failed: \(error.localizedDescription)"
            setStatus(message, isError: true)
            record(method: method, path: path, detail: message, statusCode: nil, isError: true)
            return
        }

        var message = networkError.localizedDescription
        if let response = networkError.response {
            message = Self.describe(response)
            responseText = Self.prettyJSON(from: response.data)
            lastResponse = NetworkingResponseSummary(
                statusCode: response.statusCode,
                contentType: response.header(named: "Content-Type"),
                byteCount: response.data.count,
                elapsedMilliseconds: requestStartedAt.map { elapsedMilliseconds(since: $0) } ?? 0,
                url: response.url
            )
        }

        let status = networkError.statusCode.map { "HTTP \($0) · " } ?? ""
        let description = "NetworkError · \(status)\(message)"
        setStatus(description, isError: true)
        record(
            method: method,
            path: path,
            detail: "\(status)\(message)",
            statusCode: networkError.statusCode,
            isError: true
        )
    }

    private func record(
        method: HTTPMethod,
        path: String,
        detail: String,
        statusCode: Int?,
        isError: Bool
    ) {
        callHistory.insert(
            NetworkingCallRecord(
                method: method,
                path: path,
                detail: detail,
                statusCode: statusCode,
                isError: isError
            ),
            at: 0
        )

        guard logsDiagnostics else { return }

        let line = DataMasker.mask("NetworkingViewModel: \(method.rawValue) \(path) -> \(detail)")
        if isError {
            logger.error(line)
        } else {
            logger.info(line)
        }
    }

    private func setStatus(_ message: String, isError: Bool) {
        statusMessage = message
        isErrorMessage = isError
    }

    private func refreshBearerStatus() {
        if let token = session.currentSession?.accessToken {
            bearerStatus = DataMasker.mask("Bearer \(token)")
        } else {
            bearerStatus = "No active bearer token"
        }
    }

    private func elapsedMilliseconds(since start: Date) -> Int {
        max(0, Int((Date().timeIntervalSince(start) * 1000).rounded()))
    }

    private static func describe(_ response: NetworkResponse) -> String {
        if let decoded = try? response.decode(SampleAPIResponse.self) {
            return decoded.message
        }
        if let text = String(data: response.data, encoding: .utf8), !text.isEmpty {
            return text
        }
        return "No response body."
    }

    private static func prettyJSON(from data: Data) -> String {
        guard !data.isEmpty else { return "<empty body>" }
        if let object = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: pretty, encoding: .utf8) {
            return text
        }
        return String(data: data, encoding: .utf8) ?? "<binary>"
    }

    private func startListeningForCallbacks() {
        callbackObserver = NotificationCenter.default.addObserver(
            forName: .sampleNetworkError,
            object: nil,
            queue: .main
        ) { [weak self] note in
            Task { @MainActor [weak self] in
                self?.recordCallback(note, title: "onError")
            }
        }

        authObserver = NotificationCenter.default.addObserver(
            forName: .sampleNetworkAuthenticationFailure,
            object: nil,
            queue: .main
        ) { [weak self] note in
            Task { @MainActor [weak self] in
                self?.recordCallback(note, title: "onAuthenticationFailure")
            }
        }
    }

    private func recordCallback(_ note: Notification, title: String) {
        let status = note.userInfo?["status"] as? Int ?? -1
        let path = note.userInfo?["path"] as? String ?? "unknown"
        callbackEvents.insert("\(title): HTTP \(status) \(path)", at: 0)
    }
}
