import Foundation

/// Public contract exposing device model, version, and build environment information.
public protocol DeviceInfoProtocol: Sendable {
    /// The hardware machine identifier reported by the system (for example, `iPhone15,3`, `arm64`, or `x86_64`).
    var deviceModel: String { get }

    /// The operating system version string for the current environment.
    var osVersion: String { get }

    /// The application marketing version (`CFBundleShortVersionString`), defaulting to `0.0.0` when unavailable.
    var appVersion: String { get }

    /// The application build number (`CFBundleVersion`), defaulting to `0` when unavailable.
    var buildNumber: String { get }

    /// The host application bundle identifier, defaulting to `unknown` when unavailable.
    var bundleIdentifier: String { get }

    /// The host application display name, defaulting to `unknown` when unavailable.
    var appName: String { get }

    /// Indicates whether the current process is running on a simulator.
    var isSimulator: Bool { get }

    /// Indicates whether the SDK was compiled with debug assertions enabled.
    var isDebugBuild: Bool { get }

    /// Compares the application marketing version against a minimum version.
    /// - Parameter version: The minimum version to compare against, for example `"2.1.0"`.
    /// - Returns: `true` when `appVersion` is greater than or equal to `version`; otherwise `false`.
    func isAppVersionAtLeast(_ version: String) -> Bool

    /// Determines whether an application update is required for the supplied minimum version.
    /// - Parameter minimumVersion: The minimum supported application version.
    /// - Returns: `true` when `appVersion` is lower than `minimumVersion`; otherwise `false`.
    func isUpdateRequired(minimumVersion: String) -> Bool

    /// Compares the operating system version against a minimum version.
    /// - Parameter version: The minimum version to compare against, for example `"17.0"`.
    /// - Returns: `true` when the current OS version is greater than or equal to `version`; otherwise `false`.
    func isOSVersionAtLeast(_ version: String) -> Bool
}

public extension DeviceInfoProtocol {
    func isAppVersionAtLeast(_ version: String) -> Bool {
        guard let current = SemanticVersion(appVersion), let minimum = SemanticVersion(version) else {
            return false
        }
        return current >= minimum
    }

    func isUpdateRequired(minimumVersion: String) -> Bool {
        guard let current = SemanticVersion(appVersion), let minimum = SemanticVersion(minimumVersion) else {
            return false
        }
        return current < minimum
    }

    func isOSVersionAtLeast(_ version: String) -> Bool {
        guard let current = SemanticVersion(extractingFrom: osVersion), let minimum = SemanticVersion(version) else {
            return false
        }
        return current >= minimum
    }
}
