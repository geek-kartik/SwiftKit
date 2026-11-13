import Foundation
@testable import SwiftKit

/// Recording logger used to verify module consumers without touching OSLog.
internal final class MockLogger: LoggerProtocol, Sendable {
    internal struct Entry: Equatable {
        let message: String
        let level: LogLevel
        let file: String
        let function: String
        let line: Int
    }

    private let entries = ThreadSafeBox<[Entry]>([])

    internal var recordedEntries: [Entry] {
        entries.current
    }

    internal var recordedLevels: [LogLevel] {
        entries.current.map(\.level)
    }

    internal func log(
        _ message: String,
        level: LogLevel,
        file: String,
        function: String,
        line: Int
    ) {
        let entry = Entry(message: message, level: level, file: file, function: function, line: line)
        entries.mutate { $0.append(entry) }
    }
}

/// Recording log destination used to verify OSLogger filtering and sanitization.
internal final class RecordingLogOutput: LogOutput, Sendable {
    internal struct Entry: Equatable {
        let message: String
        let level: LogLevel
    }

    private let entries = ThreadSafeBox<[Entry]>([])

    internal var recordedEntries: [Entry] {
        entries.current
    }

    internal var recordedLevels: [LogLevel] {
        entries.current.map(\.level)
    }

    internal func write(
        message: String,
        level: LogLevel,
        file: String,
        function: String,
        line: Int
    ) {
        let entry = Entry(message: message, level: level)
        entries.mutate { $0.append(entry) }
    }
}
