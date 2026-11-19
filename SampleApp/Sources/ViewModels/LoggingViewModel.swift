import Foundation
import SwiftUI
import SwiftKit

/// In-memory representation of a dispatched log entry for the UI log console.
public struct DispatchedLogEntry: Identifiable, Sendable {
    public let id = UUID()
    public let timestamp: Date
    public let level: LogLevel
    public let message: String

    public init(level: LogLevel, message: String, timestamp: Date = Date()) {
        self.level = level
        self.message = message
        self.timestamp = timestamp
    }
}

/// ViewModel demonstrating `LoggerProtocol` operations across all supported `LogLevel`s.
@MainActor
public final class LoggingViewModel: ObservableObject {
    @Published public var customMessage: String = "Test log message from SampleApp"
    @Published public var selectedLogLevel: LogLevel = .info
    @Published public var dispatchedLogs: [DispatchedLogEntry] = []

    // Sensitive data masking demonstration fields
    @Published public var sampleBearerInput: String = "Bearer secret_jwt_token_12345"
    @Published public var sampleEmailInput: String = "sensitive.user@corp.internal"
    @Published public var maskingStatusInfo: String = "SDK configuration has isMaskingEnabled = true. The SDK automatically masks sensitive tokens and emails in OSLog."

    private let logger: LoggerProtocol

    public init(logger: LoggerProtocol? = nil) {
        self.logger = logger ?? SDKService.shared.logger
    }

    /// Logs a debug diagnostic message using `logger.debug`.
    public func logDebug(customText: String? = nil) {
        let msg = customText ?? "Diagnostic debug state: cache initialized with zero items"
        logger.debug(msg)
        recordEntry(level: .debug, message: msg)
    }

    /// Logs an info message using `logger.info`.
    public func logInfo(customText: String? = nil) {
        let msg = customText ?? "User opened the diagnostic console dashboard"
        logger.info(msg)
        recordEntry(level: .info, message: msg)
    }

    /// Logs a warning message using `logger.warning`.
    public func logWarning(customText: String? = nil) {
        let msg = customText ?? "High memory watermark reached: threshold approaching 80%"
        logger.warning(msg)
        recordEntry(level: .warning, message: msg)
    }

    /// Logs an error message using `logger.error`.
    public func logError(customText: String? = nil) {
        let msg = customText ?? "Network socket connection timed out after 30 seconds"
        logger.error(msg)
        recordEntry(level: .error, message: msg)
    }

    /// Logs a message at an arbitrary `LogLevel` using `logger.log(_:level:file:function:line:)`.
    public func logCustom() {
        guard !customMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        logger.log(
            customMessage,
            level: selectedLogLevel,
            file: #fileID,
            function: #function,
            line: #line
        )
        recordEntry(level: selectedLogLevel, message: customMessage)
    }

    /// Demonstrates the SDK's automatic data masking capabilities.
    /// Notice: `DataMasker` protects Authorization Bearer tokens and emails automatically.
    public func demonstrateAutomaticMasking() {
        let messageWithSensitiveData = "Dispatching request with \(sampleBearerInput) for account \(sampleEmailInput)"
        logger.info(messageWithSensitiveData)
        recordEntry(level: .info, message: messageWithSensitiveData)
        maskingStatusInfo = "Dispatched log with token and email. In OSLog / Console, the SDK automatically sanitized the sensitive patterns!"
    }

    /// Clears the in-app log history table.
    public func clearDispatchedLogs() {
        dispatchedLogs.removeAll()
    }

    private func recordEntry(level: LogLevel, message: String) {
        let entry = DispatchedLogEntry(level: level, message: message)
        dispatchedLogs.insert(entry, at: 0)
    }
}
