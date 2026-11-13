import Darwin
import Foundation

/// Concrete device information provider backed by system and bundle metadata.
internal final class SystemDeviceInfo: DeviceInfoProtocol, Sendable {
    internal let deviceModel: String
    internal let osVersion: String
    internal let appVersion: String
    internal let buildNumber: String

    /// Creates a device info snapshot using the supplied values.
    /// - Parameters:
    ///   - bundle: Bundle used to resolve application version metadata. Defaults to `Bundle.main`.
    ///   - osVersion: Operating system version string. Defaults to `ProcessInfo.processInfo.operatingSystemVersionString`.
    ///   - deviceModel: Hardware machine identifier. Defaults to the current `utsname` machine value.
    internal init(
        bundle: Bundle = .main,
        osVersion: String = ProcessInfo.processInfo.operatingSystemVersionString,
        deviceModel: String = SystemDeviceInfo.currentMachineIdentifier()
    ) {
        self.deviceModel = deviceModel
        self.osVersion = osVersion
        self.appVersion = Self.bundleString(for: "CFBundleShortVersionString", in: bundle, defaultValue: "0.0.0")
        self.buildNumber = Self.bundleString(for: "CFBundleVersion", in: bundle, defaultValue: "0")
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
}
