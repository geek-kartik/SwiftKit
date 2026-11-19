import Foundation
import SwiftUI
import SwiftKit

/// ViewModel presenting system and application metrics obtained through `DeviceInfoProtocol`.
@MainActor
public final class DeviceInfoViewModel: ObservableObject {
    @Published public var deviceModel: String = ""
    @Published public var osVersion: String = ""
    @Published public var appVersion: String = ""
    @Published public var buildNumber: String = ""
    @Published public var bundleIdentifier: String = ""
    @Published public var appName: String = ""
    @Published public var isSimulator: Bool = false
    @Published public var isDebugBuild: Bool = false

    // Version Comparison Demonstration State
    @Published public var comparisonTargetVersion: String = "2.0.0"
    @Published public var isAppVersionAtLeastResult: Bool = false
    @Published public var isUpdateRequiredResult: Bool = false

    @Published public var osComparisonTargetVersion: String = "16.0"
    @Published public var isOSVersionAtLeastResult: Bool = false

    private let deviceInfo: DeviceInfoProtocol
    private let logger: LoggerProtocol

    public init(
        deviceInfo: DeviceInfoProtocol? = nil,
        logger: LoggerProtocol? = nil
    ) {
        self.deviceInfo = deviceInfo ?? SDKService.shared.deviceInfo
        self.logger = logger ?? SDKService.shared.logger
        loadDeviceInfo()
    }

    /// Loads metadata from the SDK's `DeviceInfoProtocol`.
    public func loadDeviceInfo() {
        deviceModel = deviceInfo.deviceModel
        osVersion = deviceInfo.osVersion
        appVersion = deviceInfo.appVersion
        buildNumber = deviceInfo.buildNumber
        bundleIdentifier = deviceInfo.bundleIdentifier
        appName = deviceInfo.appName
        isSimulator = deviceInfo.isSimulator
        isDebugBuild = deviceInfo.isDebugBuild

        evaluateAppVersion()
        evaluateOSVersion()

        logger.debug("DeviceInfo: loaded metadata for model '\(deviceModel)', OS '\(osVersion)'")
    }

    /// Evaluates application version comparisons using `isAppVersionAtLeast` and `isUpdateRequired`.
    public func evaluateAppVersion() {
        isAppVersionAtLeastResult = deviceInfo.isAppVersionAtLeast(comparisonTargetVersion)
        isUpdateRequiredResult = deviceInfo.isUpdateRequired(minimumVersion: comparisonTargetVersion)
        logger.debug("DeviceInfo: evaluated target version '\(comparisonTargetVersion)': atLeast=\(isAppVersionAtLeastResult), updateRequired=\(isUpdateRequiredResult)")
    }

    /// Evaluates OS version comparison using `isOSVersionAtLeast`.
    public func evaluateOSVersion() {
        isOSVersionAtLeastResult = deviceInfo.isOSVersionAtLeast(osComparisonTargetVersion)
        logger.debug("DeviceInfo: evaluated OS target version '\(osComparisonTargetVersion)': atLeast=\(isOSVersionAtLeastResult)")
    }
}
