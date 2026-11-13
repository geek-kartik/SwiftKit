import Foundation

/// Public contract exposing device model and version information for the host environment.
public protocol DeviceInfoProtocol: Sendable {
    /// The hardware machine identifier reported by the system (for example, `iPhone15,3`, `arm64`, or `x86_64`).
    var deviceModel: String { get }

    /// The operating system version string for the current environment.
    var osVersion: String { get }

    /// The application marketing version (`CFBundleShortVersionString`), defaulting to `0.0.0` when unavailable.
    var appVersion: String { get }

    /// The application build number (`CFBundleVersion`), defaulting to `0` when unavailable.
    var buildNumber: String { get }
}
