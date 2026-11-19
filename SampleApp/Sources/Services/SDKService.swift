import Foundation
import SwiftKit

/// Abstraction interface providing dependency injection access to SwiftKit SDK modules.
public protocol SDKServiceProtocol: AnyObject, Sendable {
    var secureStorage: SecureStorageProtocol { get }
    var deviceInfo: DeviceInfoProtocol { get }
    var connectivity: ConnectivityMonitorProtocol { get }
    var logger: LoggerProtocol { get }
    var session: SessionManagerProtocol { get }
    var networkClient: NetworkClientProtocol { get }
}

/// Concrete production service wrapping the public `SwiftKit.shared` facade.
public final class SDKService: SDKServiceProtocol, @unchecked Sendable {
    public static let shared = SDKService()

    private init() {}

    public var secureStorage: SecureStorageProtocol {
        SwiftKit.shared.secureStorage
    }

    public var deviceInfo: DeviceInfoProtocol {
        SwiftKit.shared.deviceInfo
    }

    public var connectivity: ConnectivityMonitorProtocol {
        SwiftKit.shared.connectivity
    }

    public var logger: LoggerProtocol {
        SwiftKit.shared.logger
    }

    public var session: SessionManagerProtocol {
        SwiftKit.shared.session
    }

    public var networkClient: NetworkClientProtocol {
        SwiftKit.shared.networkClient
    }
}
