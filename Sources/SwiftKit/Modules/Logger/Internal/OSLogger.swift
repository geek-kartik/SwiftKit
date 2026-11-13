import Foundation
import OSLog

/// Destination that receives already-filtered and sanitized log entries.
///
/// The abstraction exists solely so filtering and formatting can be verified in
/// unit tests without reading the system Console output.
internal protocol LogOutput: Sendable {
    /// Writes a single sanitized entry to the destination.
    /// - Parameters:
    ///   - message: The sanitized message body.
    ///   - level: The severity of the entry.
    ///   - file: The originating source file.
    ///   - function: The originating function.
    ///   - line: The originating source line.
    func write(message: String, level: LogLevel, file: String, function: String, line: Int)
}

/// Apple OSLog-backed output using privacy-preserving interpolation.
internal struct OSLogOutput: LogOutput {
    private let systemLogger: os.Logger

    internal init(subsystem: String, category: String) {
        self.systemLogger = os.Logger(subsystem: subsystem, category: category)
    }

    internal func write(message: String, level: LogLevel, file: String, function: String, line: Int) {
        let fileName = (file as NSString).lastPathComponent
        let prefix = "[\(level.label)] [\(fileName):\(line)] \(function) -> "

        switch level {
        case .debug:
            systemLogger.debug("\(prefix, privacy: .public)\(message, privacy: .private)")
        case .info:
            systemLogger.info("\(prefix, privacy: .public)\(message, privacy: .private)")
        case .warning:
            systemLogger.notice("\(prefix, privacy: .public)\(message, privacy: .private)")
        case .error:
            systemLogger.error("\(prefix, privacy: .public)\(message, privacy: .private)")
        case .none:
            break
        }
    }
}

/// Concrete logger delegating to Apple's unified logging system `os.Logger` with data masking.
internal final class OSLogger: LoggerProtocol, Sendable {
    private let configuration: LogConfiguration
    private let output: LogOutput

    /// Creates an OSLog-backed logger.
    /// - Parameter configuration: The configuration governing filtering and masking.
    internal convenience init(configuration: LogConfiguration) {
        self.init(
            configuration: configuration,
            output: OSLogOutput(subsystem: configuration.subsystem, category: configuration.category)
        )
    }

    /// Creates a logger with an injected output destination for testing.
    /// - Parameters:
    ///   - configuration: The configuration governing filtering and masking.
    ///   - output: The destination receiving sanitized entries.
    internal init(configuration: LogConfiguration, output: LogOutput) {
        self.configuration = configuration
        self.output = output
    }

    internal func log(
        _ message: String,
        level: LogLevel,
        file: String,
        function: String,
        line: Int
    ) {
        guard configuration.isEnabled else {
            return
        }

        guard level != .none, level >= configuration.minimumLevel else {
            return
        }

        let processedMessage = configuration.isMaskingEnabled ? DataMasker.mask(message) : message
        output.write(message: processedMessage, level: level, file: file, function: function, line: line)
    }
}
