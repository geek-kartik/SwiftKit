import Darwin
import Foundation

/// Concrete device information provider backed by system and bundle metadata.
internal final class SystemDeviceInfo: DeviceInfoProtocol, Sendable {
    internal let deviceModel: String
    internal let osVersion: String
    internal let appVersion: String
    internal let buildNumber: String
    internal let bundleIdentifier: String
    internal let appName: String
    internal let isSimulator: Bool
    internal let isDebugBuild: Bool

    private let osVersionNumber: SemanticVersion

    /// Creates a device info snapshot using the supplied values.
    /// - Parameters:
    ///   - bundle: Bundle used to resolve application metadata. Defaults to `Bundle.main`.
    ///   - osVersion: Operating system version string. Defaults to `ProcessInfo.processInfo.operatingSystemVersionString`.
    ///   - operatingSystemVersion: Numeric operating system version used for comparisons. Defaults to `ProcessInfo.processInfo.operatingSystemVersion`.
    ///   - deviceModel: Hardware machine identifier. Defaults to the current `utsname` machine value.
    ///   - isSimulator: Simulator indicator. Defaults to the current build target.
    ///   - isDebugBuild: Debug build indicator. Defaults to the current compilation configuration.
    internal init(
        bundle: Bundle = .main,
        osVersion: String = ProcessInfo.processInfo.operatingSystemVersionString,
        operatingSystemVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion,
        deviceModel: String = SystemDeviceInfo.currentMachineIdentifier(),
        isSimulator: Bool = SystemDeviceInfo.currentIsRunningOnSimulator,
        isDebugBuild: Bool = SystemDeviceInfo.currentIsDebugBuild
    ) {
        self.deviceModel = deviceModel
        self.osVersion = osVersion
        self.appVersion = Self.bundleString(for: "CFBundleShortVersionString", in: bundle, defaultValue: "0.0.0")
        self.buildNumber = Self.bundleString(for: "CFBundleVersion", in: bundle, defaultValue: "0")
        self.bundleIdentifier = Self.bundleIdentifier(in: bundle)
        self.appName = Self.appName(in: bundle)
        self.isSimulator = isSimulator
        self.isDebugBuild = isDebugBuild
        self.osVersionNumber = SemanticVersion(
            major: operatingSystemVersion.majorVersion,
            minor: operatingSystemVersion.minorVersion,
            patch: operatingSystemVersion.patchVersion
        )
    }

    internal func isOSVersionAtLeast(_ version: String) -> Bool {
        guard let minimum = SemanticVersion(version) else {
            return false
        }
        return osVersionNumber >= minimum
    }

    internal static var currentIsRunningOnSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    internal static var currentIsDebugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    internal static func currentMachineIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: Int(_SYS_NAMELEN)) { cString in
                String(cString: cString)
            }
        }
    }

    private static func bundleString(for key: String, in bundle: Bundle, defaultValue: String) -> String {
        let value = bundle.object(forInfoDictionaryKey: key) as? String
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return defaultValue
        }
        return value
    }

    private static func bundleIdentifier(in bundle: Bundle) -> String {
        guard let value = bundle.bundleIdentifier, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "unknown"
        }
        return value
    }

    private static func appName(in bundle: Bundle) -> String {
        let displayName = bundleString(for: "CFBundleDisplayName", in: bundle, defaultValue: "")
        guard displayName.isEmpty else {
            return displayName
        }

        let name = bundleString(for: "CFBundleName", in: bundle, defaultValue: "")
        guard name.isEmpty else {
            return name
        }

        return "unknown"
    }
}
