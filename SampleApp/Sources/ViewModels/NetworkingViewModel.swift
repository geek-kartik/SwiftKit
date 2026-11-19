import Foundation
import SwiftUI
import SwiftKit

public struct NetworkingCallRecord: Identifiable, Sendable {
    public let id = UUID()
    public let timestamp: Date
    public let method: HTTPMethod
    public let path: String
    public let detail: String
    public let isError: Bool

    public init(
        method: HTTPMethod,
        path: String,
        detail: String,
        isError: Bool,
        timestamp: Date = Date()
    ) {
        self.method = method
        self.path = path
        self.detail = detail
        self.isError = isError
        self.timestamp = timestamp
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

    private let networkClient: NetworkClientProtocol
    private let session: SessionManagerProtocol
    private let logger: LoggerProtocol
    private var callbackObserver: NSObjectProtocol?
    private var authObserver: NSObjectProtocol?

    public init(
        networkClient: NetworkClientProtocol? = nil,
        session: SessionManagerProtocol? = nil,
        logger: LoggerProtocol? = nil
    ) {
        self.networkClient = networkClient ?? SDKService.shared.networkClient
        self.session = session ?? SDKService.shared.session
        self.logger = logger ?? SDKService.shared.logger
        startListeningForCallbacks()
        refreshBearerStatus()
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
        defer { isLoading = false }

        do {
            try await execute(method: method, path: path, body: body, allowRetry: true)
            refreshBearerStatus()
        } catch {
            present(error)
        }
    }

    public func clearHistory() {
        callHistory.removeAll()
        callbackEvents.removeAll()
    }

    private func execute(
        method: HTTPMethod,
        path: String,
        body: String?,
        allowRetry: Bool
    ) async throws {
        let request = try makeRequest(method: method, path: path, body: body)

        do {
            if method == .delete {
                let response = try await networkClient.send(request)
                let payload = String(data: response.data, encoding: .utf8) ?? "<binary>"
                let detail = "HTTP \(response.statusCode) \(payload)"
                responseText = detail
                record(method: method, path: path, detail: detail, isError: false)
            } else {
                let decoded: SampleAPIResponse = try await networkClient.send(request, as: SampleAPIResponse.self)
                let detail = "\(decoded.status) · \(decoded.message)"
                responseText = detail
                record(method: method, path: path, detail: detail, isError: false)
            }

            setStatus("\(method.rawValue) \(path) completed.", isError: false)
        } catch let error as NetworkError where error.statusCode == 401 && allowRetry {
            didRetryAfter401 = true
            setStatus("Received 401. Refreshing the session and retrying once…", isError: false)

            do {
                let refreshed = try await session.refreshSession()
                setStatus("Refreshed \(refreshed.userID ?? "session"). Retrying request…", isError: false)
                try await execute(method: method, path: path, body: body, allowRetry: false)
            } catch {
                present(error)
            }
        }
    }

    private func makeRequest(method: HTTPMethod, path: String, body: String?) throws -> NetworkRequest {
        var request = try NetworkRequest(path: path, method: method)

        if method != .get, let body, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request = try request.withJSONBody(SampleJSONBody(message: body))
        }

        return request
    }

    private func present(_ error: Error) {
        if let networkError = error as? NetworkError {
            let status = networkError.statusCode.map { " (HTTP \($0))" } ?? ""
            let message = "NetworkError\(status): \(networkError.localizedDescription)"
            setStatus(message, isError: true)
            record(method: selectedMethod, path: path, detail: message, isError: true)
        } else {
            let message = "Request failed: \(error.localizedDescription)"
            setStatus(message, isError: true)
            record(method: selectedMethod, path: path, detail: message, isError: true)
        }
    }

    private func record(method: HTTPMethod, path: String, detail: String, isError: Bool) {
        callHistory.insert(
            NetworkingCallRecord(method: method, path: path, detail: detail, isError: isError),
            at: 0
        )
        logger.info("NetworkingViewModel: \(method.rawValue) \(path) -> \(detail)")
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
