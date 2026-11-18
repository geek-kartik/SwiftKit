import Foundation
import SwiftUI
import SwiftKit

/// Record of a connectivity status transition event.
public struct ConnectivityEvent: Identifiable, Sendable {
    public let id = UUID()
    public let timestamp: Date
    public let status: ConnectivityStatus

    public init(status: ConnectivityStatus, timestamp: Date = Date()) {
        self.status = status
        self.timestamp = timestamp
    }
}

/// ViewModel managing real-time connectivity observation via `ConnectivityMonitorProtocol`.
@MainActor
public final class ConnectivityViewModel: ObservableObject {
    @Published public var currentStatus: ConnectivityStatus = .unknown
    @Published public var isMonitoring: Bool = false
    @Published public var hasActiveObserver: Bool = false
    @Published public var eventLog: [ConnectivityEvent] = []

    private let connectivity: ConnectivityMonitorProtocol
    private let logger: LoggerProtocol
    private var observationToken: ConnectivityObservationToken?

    public init(
        connectivity: ConnectivityMonitorProtocol? = nil,
        logger: LoggerProtocol? = nil
    ) {
        self.connectivity = connectivity ?? SDKService.shared.connectivity
        self.logger = logger ?? SDKService.shared.logger
        self.currentStatus = self.connectivity.currentStatus
        self.isMonitoring = self.connectivity.isMonitoring
    }

    deinit {
        // Observer cleanup on deallocation
        if let token = observationToken {
            connectivity.removeObserver(token)
        }
    }

    /// Starts system network-path monitoring.
    public func startMonitoring() {
        connectivity.start()
        isMonitoring = connectivity.isMonitoring
        currentStatus = connectivity.currentStatus
        logger.info("ConnectivityViewModel: monitoring started. Current status: \(currentStatus.rawValue)")

        if observationToken == nil {
            registerObserver()
        }
    }

    /// Stops network-path monitoring and removes the observer.
    public func stopMonitoring() {
        unregisterObserver()
        connectivity.stop()
        isMonitoring = connectivity.isMonitoring
        currentStatus = connectivity.currentStatus
        logger.info("ConnectivityViewModel: monitoring stopped. Retained status: \(currentStatus.rawValue)")
    }

    /// Toggles active observer registration.
    public func toggleObserver() {
        if hasActiveObserver {
            unregisterObserver()
        } else {
            registerObserver()
        }
    }

    /// Registers observer with `ConnectivityMonitorProtocol.addObserver`.
    public func registerObserver() {
        guard observationToken == nil else { return }

        logger.debug("ConnectivityViewModel: registering observer...")
        let token = connectivity.addObserver { [weak self] newStatus in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.currentStatus = newStatus
                self.isMonitoring = self.connectivity.isMonitoring
                self.eventLog.insert(ConnectivityEvent(status: newStatus), at: 0)
                self.logger.info("ConnectivityViewModel: status transitioned -> \(newStatus.rawValue)")
            }
        }
        observationToken = token
        hasActiveObserver = true
    }

    /// Removes observer using `ConnectivityMonitorProtocol.removeObserver`.
    public func unregisterObserver() {
        guard let token = observationToken else { return }
        connectivity.removeObserver(token)
        observationToken = nil
        hasActiveObserver = false
        logger.debug("ConnectivityViewModel: unregistered observer.")
    }

    /// Clears the recorded transition event history.
    public func clearEventLog() {
        eventLog.removeAll()
    }
}
