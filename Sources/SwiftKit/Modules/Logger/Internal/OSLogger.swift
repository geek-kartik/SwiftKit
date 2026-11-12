import Foundation
import OSLog

/// Concrete logger delegating to Apple's unified logging system `os.Logger` with data masking.
internal final class OSLogger: LoggerProtocol, Sendable {
    private let systemLogger: os.Logger
    private let configuration: LogConfiguration

    internal init(configuration: LogConfiguration) {
        self.configuration = configuration
        self.systemLogger = os.Logger(subsystem: configuration.subsystem, category: configuration.category)
    }

    internal func log(
        _ message: String,
        level: LogLevel,
        file: String,
        function: String,
        line: Int
    ) {
        guard level >= configuration.minimumLevel && level != .none else {
            return
        }

        let processedMessage = configuration.isMaskingEnabled ? DataMasker.mask(message) : message
        let fileName = (file as NSString).lastPathComponent
        let formattedEntry = "[\(level.label)] [\(fileName):\(line)] \(function) -> \(processedMessage)"

        switch level {
        case .debug:
            systemLogger.debug("\(formattedEntry, privacy: .public)")
        case .info:
            systemLogger.info("\(formattedEntry, privacy: .public)")
        case .warning:
            systemLogger.notice("\(formattedEntry, privacy: .public)")
        case .error:
            systemLogger.error("\(formattedEntry, privacy: .public)")
        case .none:
            break
        }
    }
}
