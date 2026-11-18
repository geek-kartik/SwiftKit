import Foundation
import SwiftKit
@testable import SampleApp

/// In-memory implementation of `SecureStorageProtocol` for SampleApp unit tests.
public final class MockSecureStorage: SecureStorageProtocol, @unchecked Sendable {
    private var storage: [String: Data] = [:]
    private let lock = NSLock()

    public var shouldThrowOnWrite: Bool = false
    public var shouldThrowOnRead: Bool = false

    public init() {}

    public func setData(_ data: Data, forKey key: String) throws {
        lock.lock()
        defer { lock.unlock() }

        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SecureStorageError.invalidKey
        }
        if shouldThrowOnWrite {
            throw SecureStorageError.writeFailed(status: -50)
        }
        storage[key] = data
    }

    public func data(forKey key: String) throws -> Data {
        lock.lock()
        defer { lock.unlock() }

        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SecureStorageError.invalidKey
        }
        if shouldThrowOnRead {
            throw SecureStorageError.readFailed(status: -50)
        }
        guard let value = storage[key] else {
            throw SecureStorageError.itemNotFound(key: key)
        }
        return value
    }

    public func contains(_ key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return storage[key] != nil
    }

    public func remove(forKey key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        storage.removeValue(forKey: key)
    }

    public func removeAll() throws {
        lock.lock()
        defer { lock.unlock() }
        storage.removeAll()
    }
}

/// Mock implementation of `DeviceInfoProtocol` for SampleApp unit tests.
public final class MockDeviceInfo: DeviceInfoProtocol, @unchecked Sendable {
    public var deviceModel: String = "iPhone15,2"
    public var osVersion: String = "17.4"
    public var appVersion: String = "1.2.0"
    public var buildNumber: String = "42"
    public var bundleIdentifier: String = "com.swiftkit.sampleapp"
    public var appName: String = "SampleApp"
    public var isSimulator: Bool = true
    public var isDebugBuild: Bool = true

    public init() {}
}

/// Mock implementation of `ConnectivityMonitorProtocol` for SampleApp unit tests.
public final class MockConnectivityMonitor: ConnectivityMonitorProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var observers: [ConnectivityObservationToken: @Sendable (ConnectivityStatus) -> Void] = [:]

    public var currentStatus: ConnectivityStatus = .unknown
    public var isMonitoring: Bool = false

    public init(initialStatus: ConnectivityStatus = .unknown) {
        self.currentStatus = initialStatus
    }

    public func start() {
        lock.lock()
        defer { lock.unlock() }
        isMonitoring = true
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        isMonitoring = false
    }

    public func addObserver(_ observer: @escaping @Sendable (ConnectivityStatus) -> Void) -> ConnectivityObservationToken {
        lock.lock()
        let token = ConnectivityObservationToken()
        observers[token] = observer
        let snapshot = currentStatus
        lock.unlock()

        observer(snapshot)
        return token
    }

    public func removeObserver(_ token: ConnectivityObservationToken) {
        lock.lock()
        defer { lock.unlock() }
        observers.removeValue(forKey: token)
    }

    /// Simulates a network transition event.
    public func simulateStatusChange(_ newStatus: ConnectivityStatus) {
        lock.lock()
        currentStatus = newStatus
        let currentObservers = Array(observers.values)
        lock.unlock()

        for observer in currentObservers {
            observer(newStatus)
        }
    }
}

/// Mock implementation of `LoggerProtocol` recording calls for verification.
public final class MockLogger: LoggerProtocol, @unchecked Sendable {
    private let lock = NSLock()
    public var loggedMessages: [(level: LogLevel, message: String)] = []

    public init() {}

    public func log(_ message: String, level: LogLevel, file: String, function: String, line: Int) {
        lock.lock()
        defer { lock.unlock() }
        loggedMessages.append((level, message))
    }
}
