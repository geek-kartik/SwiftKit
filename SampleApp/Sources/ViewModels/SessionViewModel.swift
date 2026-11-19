import Foundation
import SwiftUI
import SwiftKit

public struct SessionEventRecord: Identifiable, Sendable {
    public let id = UUID()
    public let timestamp: Date
    public let event: SessionEvent

    public init(event: SessionEvent, timestamp: Date = Date()) {
        self.event = event
        self.timestamp = timestamp
    }

    public var title: String {
        switch event {
        case .authenticated:
            return "Authenticated"
        case .refreshed:
            return "Refreshed"
        case .loggedOut:
            return "Logged Out"
        case .expired:
            return "Expired"
        case .unauthorized:
            return "Unauthorized (401)"
        }
    }
}

@MainActor
public final class SessionViewModel: ObservableObject {
    @Published public var accessTokenInput = "sample_access_token_abc123"
    @Published public var refreshTokenInput = "sample_refresh_token_xyz789"
    @Published public var lifetimeSeconds: Double = 3600
    @Published public var stateTitle = "Unauthenticated"
    @Published public var isAuthenticated = false
    @Published public var userID = "—"
    @Published public var maskedAccessToken = "—"
    @Published public var expiryText = "—"
    @Published public var statusMessage = ""
    @Published public var isErrorMessage = false
    @Published public var events: [SessionEventRecord] = []

    private let session: SessionManagerProtocol
    private let logger: LoggerProtocol
    private var observerToken: SessionObservationToken?

    public init(
        session: SessionManagerProtocol? = nil,
        logger: LoggerProtocol? = nil
    ) {
        self.session = session ?? SDKService.shared.session
        self.logger = logger ?? SDKService.shared.logger
        refreshSnapshot()
        registerObserver()
    }

    deinit {
        if let token = observerToken {
            session.removeObserver(token)
        }
    }

    public func startSession() {
        let session = Session(
            accessToken: accessTokenInput,
            refreshToken: refreshTokenInput,
            expiresAt: Date().addingTimeInterval(lifetimeSeconds),
            userID: "sample-user-42"
        )

        do {
            try self.session.startSession(session)
            setStatus("Session started and persisted to Keychain.", isError: false)
            refreshSnapshot()
        } catch {
            setStatus("Start failed: \(error.localizedDescription)", isError: true)
        }
    }

    public func restoreSession() {
        do {
            if let restored = try session.restoreSession() {
                setStatus("Restored session for \(restored.userID ?? "unknown user").", isError: false)
            } else {
                setStatus("No persisted session was found.", isError: false)
            }
            refreshSnapshot()
        } catch {
            setStatus("Restore failed: \(error.localizedDescription)", isError: true)
        }
    }

    public func validateExpiry() {
        session.validateExpiry()
        setStatus("Expiry validation completed.", isError: false)
        refreshSnapshot()
    }

    public func refreshSynchronously() {
        guard let current = session.currentSession else {
            setStatus("No active session to refresh.", isError: true)
            return
        }

        do {
            try session.refreshSession(
                accessToken: "\(current.accessToken)_sync",
                refreshToken: current.refreshToken,
                expiresAt: Date().addingTimeInterval(lifetimeSeconds)
            )
            setStatus("Synchronous refresh committed.", isError: false)
            refreshSnapshot()
        } catch {
            setStatus("Sync refresh failed: \(error.localizedDescription)", isError: true)
        }
    }

    public func refreshAsynchronously() async {
        do {
            let refreshed = try await session.refreshSession()
            setStatus("Async refresh returned \(refreshed.userID ?? "a session").", isError: false)
            refreshSnapshot()
        } catch {
            setStatus("Async refresh failed: \(error.localizedDescription)", isError: true)
        }
    }

    public func logout() {
        do {
            try session.logout()
            setStatus("Session cleared from memory and Keychain.", isError: false)
            refreshSnapshot()
        } catch {
            setStatus("Logout failed: \(error.localizedDescription)", isError: true)
        }
    }

    public func handleUnauthorized() {
        session.handleUnauthorized()
        setStatus("Simulated HTTP 401: session cleared via handleUnauthorized().", isError: false)
        refreshSnapshot()
    }

    public func clearEvents() {
        events.removeAll()
    }

    private func registerObserver() {
        observerToken = session.addObserver { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.events.insert(SessionEventRecord(event: event), at: 0)
                self.logger.info("SessionViewModel: observer received \(event).")
                self.refreshSnapshot()
            }
        }
    }

    private func refreshSnapshot() {
        let state = session.state
        stateTitle = Self.title(for: state)
        isAuthenticated = state.isAuthenticated
        userID = state.session?.userID ?? "—"

        if let token = state.session?.accessToken {
            maskedAccessToken = DataMasker.mask("Bearer \(token)")
        } else {
            maskedAccessToken = "—"
        }

        if let expiresAt = state.session?.expiresAt {
            expiryText = expiresAt.formatted(date: .omitted, time: .standard)
        } else if case .expired = state {
            expiryText = "Expired (credentials retained)"
        } else {
            expiryText = "—"
        }
    }

    private func setStatus(_ message: String, isError: Bool) {
        statusMessage = message
        isErrorMessage = isError
    }

    private static func title(for state: SessionState) -> String {
        switch state {
        case .unauthenticated:
            return "Unauthenticated"
        case .authenticated:
            return "Authenticated"
        case .expired:
            return "Expired"
        }
    }
}
