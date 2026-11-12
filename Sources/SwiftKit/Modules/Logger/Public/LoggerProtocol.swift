import Foundation

/// Public logging contract offering standardized diagnostic output with sensitive data redaction.
public protocol LoggerProtocol: Sendable {
    /// Logs a message at the specified severity level with source code origin context.
    func log(
        _ message: String,
        level: LogLevel,
        file: String,
        function: String,
        line: Int
    )

    /// Logs a debug diagnostic message.
    func debug(
        _ message: String,
        file: String,
        function: String,
        line: Int
    )

    /// Logs an informational event message.
    func info(
        _ message: String,
        file: String,
        function: String,
        line: Int
    )

    /// Logs a warning regarding a non-fatal anomaly.
    func warning(
        _ message: String,
        file: String,
        function: String,
        line: Int
    )

    /// Logs an error detailing a failure condition.
    func error(
        _ message: String,
        file: String,
        function: String,
        line: Int
    )
}

public extension LoggerProtocol {
    func debug(
        _ message: String,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        log(message, level: .debug, file: file, function: function, line: line)
    }

    func info(
        _ message: String,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        log(message, level: .info, file: file, function: function, line: line)
    }

    func warning(
        _ message: String,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        log(message, level: .warning, file: file, function: function, line: line)
    }

    func error(
        _ message: String,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        log(message, level: .error, file: file, function: function, line: line)
    }
}
