import Foundation
import Security

/// Keychain accessibility policies controlling when stored values can be read.
public enum SecureStorageAccessibility: String, CaseIterable, Sendable {
    /// Values are readable only while the device is unlocked.
    case whenUnlocked
    /// Values are readable only while the device is unlocked and never migrate to another device.
    case whenUnlockedThisDeviceOnly
    /// Values are readable after the first unlock following a reboot.
    case afterFirstUnlock
    /// Values are readable after the first unlock following a reboot and never migrate to another device.
    case afterFirstUnlockThisDeviceOnly
    /// Values are readable only when a device passcode is set and never migrate to another device.
    case whenPasscodeSetThisDeviceOnly

    /// Corresponding Keychain Services accessibility constant.
    internal var keychainValue: CFString {
        switch self {
        case .whenUnlocked:
            return kSecAttrAccessibleWhenUnlocked
        case .whenUnlockedThisDeviceOnly:
            return kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        case .afterFirstUnlock:
            return kSecAttrAccessibleAfterFirstUnlock
        case .afterFirstUnlockThisDeviceOnly:
            return kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        case .whenPasscodeSetThisDeviceOnly:
            return kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
        }
    }
}
