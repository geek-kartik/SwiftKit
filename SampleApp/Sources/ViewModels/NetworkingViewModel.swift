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

/// The cache policies the sample exposes for a request.
public enum SampleCachePolicy: String, CaseIterable, Identifiable, Sendable {
    case protocolDefault = "Protocol default"
    case reloadIgnoringLocal = "Reload ignoring cache"
    case returnCacheDataElseLoad = "Cache else load"
    case reloadRevalidatingCacheData = "Revalidate cache"

    public var id: String { rawValue }

    /// The `URLRequest` policy applied to the request.
    public var requestPolicy: URLRequest.CachePolicy {
        switch self {
        case .protocolDefault:
            return .useProtocolCachePolicy
        case .reloadIgnoringLocal:
            return .reloadIgnoringLocalCacheData
        case .returnCacheDataElseLoad:
            return .returnCacheDataElseLoad
        case .reloadRevalidatingCacheData:
            return .reloadRevalidatingCacheData
        }
    }
}

/// Input validation failures raised before a request reaches the networking client.
public enum NetworkingInputError: Error, LocalizedError, Equatable, Sendable {
    case invalidJSONBody
    case invalidHeader(String)
    case invalidTimeout

    public var errorDescription: String? {
        switch self {
        case .invalidJSONBody:
            return "The request body is not valid JSON. Raw bodies are sent exactly as typed."
        case .invalidHeader:
            return "Invalid header line. Use the format Name: Value."
        case .invalidTimeout:
            return "The timeout must be a positive number of seconds."
        }
    }
}

@MainActor
public final class NetworkingViewModel: ObservableObject {
    @Published public var selectedMethod: HTTPMethod = .get

    /// Returns `true` when the body TextEditor should be visible.
    /// GET and DELETE methods hide the body field; POST, PUT, PATCH show it.
    public var isBodyVisible: Bool {
        selectedMethod != .get && selectedMethod != .delete
    }
    @Published public var path = "/v1/items"
    @Published public var bodyText = #"{"message":"Hello from SampleApp"}"#
    @Published public var headersText = ""
    @Published public var timeoutText = "30"
    @Published public var cachePolicy: SampleCachePolicy = .reloadIgnoringLocal
    @Published public var responseText = ""
    @Published public var statusMessage = ""
    @Published public var isErrorMessage = false
    @Published public var isLoading = false
    @Published public var didRetryAfter401 = false
    @Published public var bearerStatus = "No active bearer token"
    @Published public var callHistory: [NetworkingCallRecord] = []
    @Published public var callbackEvents: [String] = []
    @Published public var lastResponse: NetworkingResponseSummary?

    /// The number of requests currently in flight.
    @Published public private(set) var inFlightCount = 0

    /// How many duplicate sends were ignored while an identical request was in flight.
    @Published public private(set) var suppressedDuplicateCount = 0

    /// Controls whether this screen writes request results to the SDK logger.
    ///
    /// This is an app-level switch that demonstrates developer-controlled diagnostics:
    /// turn it off to keep request details out of OSLog when sharing a build.
    @Published public var logsDiagnostics = true

    /// Identifies a request for duplicate suppression.
    private struct RequestKey: Hashable {
        let method: String
        let path: String
        let body: String?
        let headers: String
        let timeout: String
        let cachePolicy: String
    }

    private let networkClient: NetworkClientProtocol
    private let session: SessionManagerProtocol
    private let logger: LoggerProtocol
    private var callbackObserver: NSObjectProtocol?
    private var authObserver: NSObjectProtocol?
    private var sessionObserverToken: SessionObservationToken?

    /// One task per distinct in-flight request. Identical keys are never inserted twice.
    private var activeTasks: [RequestKey: Task<Void, Never>] = [:]

    /// A shared refresh task so concurrent 401s trigger only one token refresh.
    private var refreshTask: Task<Session, Error>?

    /// Set while a session-ending event cancels in-flight work.
    private var sessionEndedDuringRequest = false

    public init(
        networkClient: NetworkClientProtocol? = nil,
        session: SessionManagerProtocol? = nil,
        logger: LoggerProtocol? = nil
    ) {
        self.networkClient = networkClient ?? SDKService.shared.networkClient
        self.session = session ?? SDKService.shared.session
        self.logger = logger ?? SDKService.shared.logger
        activate()
    }

    deinit {
        if let token = sessionObserverToken {
            session.removeObserver(token)
        }
        if let callbackObserver {
            NotificationCenter.default.removeObserver(callbackObserver)
        }
        if let authObserver {
            NotificationCenter.default.removeObserver(authObserver)
        }
    }

    /// Registers observers and refreshes state when the screen appears.
    public func activate() {
        startListeningForCallbacks()
        startObservingSession()
        refreshState()
    }

    /// Cancels in-flight work and removes observers when the screen disappears.
    public func cleanup() {
        for task in activeTasks.values {
            task.cancel()
        }
        if let token = sessionObserverToken {
            session.removeObserver(token)
            sessionObserverToken = nil
        }
        removeNotificationObservers()
    }

    public func send() async {
        await sendRequest(method: selectedMethod, path: path, body: bodyText)
    }

    /// Sends a request and awaits its completion.
    ///
    /// Identical requests are suppressed while one is already in flight. Cancelling the caller
    /// also cancels the underlying request.
    public func sendRequest(method: HTTPMethod, path: String, body: String? = nil) async {
        let key = makeKey(method: method, path: path, body: body)
        guard beginRequest(key) else { return }

        let task = Task { [weak self] in
            guard let self else { return }
            await self.performRequest(method: method, path: path, body: body)
        }
        activeTasks[key] = task

        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }

        finishRequest(key)
    }

    /// Cancels every in-flight request.
    public func cancelActiveRequest() {
        for task in activeTasks.values {
            task.cancel()
        }
    }

    /// Sends the protected request after invalidating the sample backend token so the
    /// `401 → refresh → retry` flow can be demonstrated repeatedly.
    public func sendProtectedRequest() async {
        guard session.isAuthenticated else {
            setStatus("Start a demo session first, then run the 401 scenario.", isError: true)
            return
        }
        await SampleBackend.shared.markTokenStale()
        await sendRequest(method: .get, path: "/v1/protected")
    }

    /// Starts an in-memory demo session with generated credentials.
    public func startDemoSession() {
        let expiresAt = Date().addingTimeInterval(3600)
        guard expiresAt > Date() else {
            setStatus("Could not create a demo session with a future expiry.", isError: true)
            return
        }

        let demo = Session(
            accessToken: Self.makeToken(prefix: "sample_access"),
            refreshToken: Self.makeToken(prefix: "sample_refresh"),
            expiresAt: expiresAt,
            userID: "network-user-42"
        )

        do {
            try session.startSession(demo)
            session.validateExpiry()
            refreshState()
            setStatus(
                "Demo session started with generated tokens; access expires at \(expiresAt.formatted(date: .omitted, time: .shortened)).",
                isError: false
            )
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
        session.validateExpiry()
        refreshBearerStatus()
    }

    // MARK: - Request lifecycle

    private func beginRequest(_ key: RequestKey) -> Bool {
        guard activeTasks[key] == nil else {
            suppressedDuplicateCount += 1
            setStatus("An identical request is already in flight. Cancel it or wait for it to finish.", isError: false)
            return false
        }

        session.validateExpiry()
        if case .expired = session.state {
            setStatus("The session expired; sign in again before sending requests.", isError: true)
            return false
        }

        didRetryAfter401 = false
        lastResponse = nil
        responseText = ""
        inFlightCount += 1
        isLoading = true
        return true
    }

    private func finishRequest(_ key: RequestKey) {
        activeTasks.removeValue(forKey: key)
        inFlightCount = activeTasks.count
        isLoading = inFlightCount > 0
        refreshBearerStatus()
    }

    private func performRequest(method: HTTPMethod, path: String, body: String?) async {
        let startedAt = Date()

        do {
            try await execute(method: method, path: path, body: body, allowRetry: true)
        } catch is CancellationError {
            presentCancellation(method: method, path: path)
        } catch let error as NetworkError where error == .cancelled {
            presentCancellation(method: method, path: path)
        } catch {
            present(error, method: method, path: path, startedAt: startedAt)
        }
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
        } catch let error as NetworkError where error.statusCode == 401 {
            guard allowRetry else {
                session.handleUnauthorized()
                refreshBearerStatus()
                let message = "Second HTTP 401 after refresh; the session was cleared."
                setStatus(message, isError: true)
                record(method: method, path: path, detail: message, statusCode: 401, isError: true)
                return
            }

            guard session.isAuthenticated else {
                let message = "HTTP 401 after logout or expiry; refresh and retry skipped."
                setStatus(message, isError: true)
                record(method: method, path: path, detail: message, statusCode: 401, isError: true)
                return
            }

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
                refreshed = try await refreshSessionSingleFlight()
            } catch {
                session.handleUnauthorized()
                refreshBearerStatus()
                let message = "Token refresh failed; the session was cleared. \(error.localizedDescription)"
                setStatus(message, isError: true)
                record(method: method, path: path, detail: message, statusCode: 401, isError: true)
                return
            }

            guard session.isAuthenticated else {
                let message = "Session ended during refresh; retry skipped."
                setStatus(message, isError: true)
                record(method: method, path: path, detail: message, statusCode: 401, isError: true)
                return
            }

            refreshBearerStatus()
            setStatus("Refreshed \(refreshed.userID ?? "the session"). Retrying request…", isError: false)
            try await execute(method: method, path: path, body: body, allowRetry: false)
        }
    }

    /// Coalesces concurrent 401 refreshes into one SDK refresh call.
    private func refreshSessionSingleFlight() async throws -> Session {
        if let refreshTask {
            return try await refreshTask.value
        }

        let session = self.session
        let task = Task<Session, Error> {
            try await session.refreshSession()
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    // MARK: - Request construction

    private func makeRequest(method: HTTPMethod, path: String, body: String?) throws -> NetworkRequest {
        var headers = try parseHeaders()
        var bodyData: Data?

        if method != .get, let body, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let data = body.data(using: .utf8) else {
                throw NetworkingInputError.invalidJSONBody
            }
            do {
                _ = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            } catch {
                throw NetworkingInputError.invalidJSONBody
            }
            bodyData = data
            headers["Content-Type"] = "application/json"
        }

        return try NetworkRequest(
            path: path,
            method: method,
            headers: headers,
            body: bodyData,
            timeoutInterval: try parseTimeout(),
            cachePolicy: cachePolicy.requestPolicy
        )
    }

    private func parseHeaders() throws -> [String: String] {
        var headers: [String: String] = [:]

        for rawLine in headersText.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            guard let separator = line.firstIndex(of: ":") else {
                throw NetworkingInputError.invalidHeader(line)
            }

            let name = line[..<separator].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else {
                throw NetworkingInputError.invalidHeader(line)
            }
            headers[name] = value
        }

        return headers
    }

    private func parseTimeout() throws -> TimeInterval? {
        let trimmed = timeoutText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let timeout = TimeInterval(trimmed), timeout > 0 else {
            throw NetworkingInputError.invalidTimeout
        }
        return timeout
    }

    private func makeKey(method: HTTPMethod, path: String, body: String?) -> RequestKey {
        RequestKey(
            method: method.rawValue,
            path: path,
            body: body,
            headers: headersText,
            timeout: timeoutText,
            cachePolicy: cachePolicy.rawValue
        )
    }

    // MARK: - Presentation

    private func present(_ error: Error, method: HTTPMethod, path: String, startedAt: Date) {
        guard let networkError = error as? NetworkError else {
            let message = error.localizedDescription
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
                elapsedMilliseconds: elapsedMilliseconds(since: startedAt),
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

    private func presentCancellation(method: HTTPMethod, path: String) {
        let endedBySession = sessionEndedDuringRequest
        sessionEndedDuringRequest = false

        let message = endedBySession
            ? "Session ended; the in-flight request was cancelled."
            : "Request cancelled."
        setStatus(message, isError: endedBySession)
        record(method: method, path: path, detail: message, statusCode: nil, isError: endedBySession)
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

    // MARK: - Session observation

    private func startObservingSession() {
        guard sessionObserverToken == nil else { return }

        sessionObserverToken = session.addObserver { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleSessionEvent(event)
            }
        }
    }

    private func handleSessionEvent(_ event: SessionEvent) {
        switch event {
        case .authenticated, .refreshed:
            sessionEndedDuringRequest = false
            refreshBearerStatus()
        case .loggedOut, .expired, .unauthorized:
            sessionEndedDuringRequest = !activeTasks.isEmpty
            for task in activeTasks.values {
                task.cancel()
            }
            refreshBearerStatus()
        }
    }

    // MARK: - Notifications

    private func startListeningForCallbacks() {
        if callbackObserver == nil {
            callbackObserver = NotificationCenter.default.addObserver(
                forName: .sampleNetworkError,
                object: nil,
                queue: .main
            ) { [weak self] note in
                Task { @MainActor [weak self] in
                    self?.recordCallback(note, title: "onError")
                }
            }
        }

        if authObserver == nil {
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
    }

    private func removeNotificationObservers() {
        if let callbackObserver {
            NotificationCenter.default.removeObserver(callbackObserver)
            self.callbackObserver = nil
        }
        if let authObserver {
            NotificationCenter.default.removeObserver(authObserver)
            self.authObserver = nil
        }
    }

    private func recordCallback(_ note: Notification, title: String) {
        let status = note.userInfo?["status"] as? Int ?? -1
        let path = note.userInfo?["path"] as? String ?? "unknown"
        callbackEvents.insert("\(title): HTTP \(status) \(path)", at: 0)
    }

    // MARK: - Utilities

    private static func makeToken(prefix: String) -> String {
        "\(prefix)_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
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
}
