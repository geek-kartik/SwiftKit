import XCTest
@testable import SwiftKit

private final class MockDeviceInfo: DeviceInfoProtocol, Sendable {
    let deviceModel: String
    let osVersion: String
    let appVersion: String
    let buildNumber: String
    let bundleIdentifier: String
    let appName: String
    let isSimulator: Bool
    let isDebugBuild: Bool

    init(
        deviceModel: String,
        osVersion: String,
        appVersion: String,
        buildNumber: String,
        bundleIdentifier: String,
        appName: String,
        isSimulator: Bool,
        isDebugBuild: Bool
    ) {
        self.deviceModel = deviceModel
        self.osVersion = osVersion
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.isSimulator = isSimulator
        self.isDebugBuild = isDebugBuild
    }
}

final class DeviceInfoTests: XCTestCase {
    override func setUp() {
        super.setUp()
        SwiftKit.resetForTesting()
    }

    override func tearDown() {
        SwiftKit.resetForTesting()
        super.tearDown()
    }

    func testSystemDeviceInfoUsesProvidedValues() {
        let bundle = makeBundle(info: [
            "CFBundleShortVersionString": "2.4.1",
            "CFBundleVersion": "42"
        ])

        let deviceInfo = SystemDeviceInfo(
            bundle: bundle,
            osVersion: "iOS 18.0",
            deviceModel: "iPhone15,3"
        )

        XCTAssertEqual(deviceInfo.deviceModel, "iPhone15,3")
        XCTAssertEqual(deviceInfo.osVersion, "iOS 18.0")
        XCTAssertEqual(deviceInfo.appVersion, "2.4.1")
        XCTAssertEqual(deviceInfo.buildNumber, "42")
    }

    func testMissingBundleInfoUsesDefaults() {
        let bundle = makeBundle(info: [:])

        let deviceInfo = SystemDeviceInfo(
            bundle: bundle,
            osVersion: "macOS 15.0",
            deviceModel: "arm64"
        )

        XCTAssertEqual(deviceInfo.appVersion, "0.0.0")
        XCTAssertEqual(deviceInfo.buildNumber, "0")
        XCTAssertEqual(deviceInfo.bundleIdentifier, "unknown")
        XCTAssertEqual(deviceInfo.appName, "unknown")
    }

    func testEmptyBundleInfoUsesDefaults() {
        let bundle = makeBundle(info: [
            "CFBundleShortVersionString": "   ",
            "CFBundleVersion": "",
            "CFBundleIdentifier": "   ",
            "CFBundleDisplayName": "   "
        ])

        let deviceInfo = SystemDeviceInfo(
            bundle: bundle,
            osVersion: "macOS 15.0",
            deviceModel: "arm64"
        )

        XCTAssertEqual(deviceInfo.appVersion, "0.0.0")
        XCTAssertEqual(deviceInfo.buildNumber, "0")
        XCTAssertEqual(deviceInfo.bundleIdentifier, "unknown")
        XCTAssertEqual(deviceInfo.appName, "unknown")
    }

    func testBundleIdentifierAndAppNameUseProvidedValues() {
        let bundle = makeBundle(info: [
            "CFBundleIdentifier": "com.example.app",
            "CFBundleDisplayName": "Example App"
        ])

        let deviceInfo = SystemDeviceInfo(
            bundle: bundle,
            osVersion: "iOS 18.0",
            deviceModel: "iPhone15,3"
        )

        XCTAssertEqual(deviceInfo.bundleIdentifier, "com.example.app")
        XCTAssertEqual(deviceInfo.appName, "Example App")
    }

    func testAppNameFallsBackToBundleName() {
        let bundle = makeBundle(info: [
            "CFBundleName": "FallbackName"
        ])

        let deviceInfo = SystemDeviceInfo(
            bundle: bundle,
            osVersion: "iOS 18.0",
            deviceModel: "iPhone15,3"
        )

        XCTAssertEqual(deviceInfo.appName, "FallbackName")
    }

    func testSimulatorAndDebugFlagsAreInjectable() {
        let enabled = SystemDeviceInfo(
            bundle: makeBundle(info: [:]),
            osVersion: "iOS 18.0",
            deviceModel: "arm64",
            isSimulator: true,
            isDebugBuild: true
        )
        let disabled = SystemDeviceInfo(
            bundle: makeBundle(info: [:]),
            osVersion: "iOS 18.0",
            deviceModel: "arm64",
            isSimulator: false,
            isDebugBuild: false
        )

        XCTAssertTrue(enabled.isSimulator)
        XCTAssertTrue(enabled.isDebugBuild)
        XCTAssertFalse(disabled.isSimulator)
        XCTAssertFalse(disabled.isDebugBuild)
    }

    func testAppVersionComparisonHelpers() {
        let deviceInfo = SystemDeviceInfo(
            bundle: makeBundle(info: ["CFBundleShortVersionString": "1.10.0"]),
            osVersion: "iOS 18.0",
            deviceModel: "iPhone15,3"
        )

        XCTAssertTrue(deviceInfo.isAppVersionAtLeast("1.9.0"))
        XCTAssertTrue(deviceInfo.isAppVersionAtLeast("1.10.0"))
        XCTAssertTrue(deviceInfo.isAppVersionAtLeast("1.10"))
        XCTAssertFalse(deviceInfo.isAppVersionAtLeast("1.10.1"))
        XCTAssertFalse(deviceInfo.isAppVersionAtLeast("not-a-version"))
    }

    func testUpdateRequiredHelper() {
        let deviceInfo = SystemDeviceInfo(
            bundle: makeBundle(info: ["CFBundleShortVersionString": "1.10.0"]),
            osVersion: "iOS 18.0",
            deviceModel: "iPhone15,3"
        )

        XCTAssertTrue(deviceInfo.isUpdateRequired(minimumVersion: "1.10.1"))
        XCTAssertTrue(deviceInfo.isUpdateRequired(minimumVersion: "2.0.0"))
        XCTAssertFalse(deviceInfo.isUpdateRequired(minimumVersion: "1.10.0"))
        XCTAssertFalse(deviceInfo.isUpdateRequired(minimumVersion: "1.0.0"))
        XCTAssertFalse(deviceInfo.isUpdateRequired(minimumVersion: "invalid"))
    }

    func testOSVersionComparisonHelper() {
        let deviceInfo = SystemDeviceInfo(
            bundle: makeBundle(info: [:]),
            osVersion: "Version 18.1 (Build 22B83)",
            operatingSystemVersion: OperatingSystemVersion(majorVersion: 18, minorVersion: 1, patchVersion: 0),
            deviceModel: "iPhone15,3"
        )

        XCTAssertTrue(deviceInfo.isOSVersionAtLeast("18.0"))
        XCTAssertTrue(deviceInfo.isOSVersionAtLeast("18.1"))
        XCTAssertFalse(deviceInfo.isOSVersionAtLeast("18.2"))
        XCTAssertFalse(deviceInfo.isOSVersionAtLeast("invalid"))
    }

    func testCurrentMachineIdentifierIsNonEmpty() {
        XCTAssertFalse(SystemDeviceInfo.currentMachineIdentifier().isEmpty)
    }

    func testFacadeResolvesInjectedDeviceInfo() {
        let config = SwiftKitConfiguration(environment: .development)
        let mock = MockDeviceInfo(
            deviceModel: "iPhone16,1",
            osVersion: "iOS 18.4",
            appVersion: "3.1.0",
            buildNumber: "310",
            bundleIdentifier: "com.example.app",
            appName: "Example App",
            isSimulator: true,
            isDebugBuild: true
        )
        let container = SDKDependencyContainer(
            configuration: config,
            logger: MockLogger(),
            deviceInfo: mock
        )

        SwiftKit.initializeForTesting(container: container)

        XCTAssertEqual(SwiftKit.shared.deviceInfo.deviceModel, "iPhone16,1")
        XCTAssertEqual(SwiftKit.shared.deviceInfo.osVersion, "iOS 18.4")
        XCTAssertEqual(SwiftKit.shared.deviceInfo.appVersion, "3.1.0")
        XCTAssertEqual(SwiftKit.shared.deviceInfo.buildNumber, "310")
        XCTAssertEqual(SwiftKit.shared.deviceInfo.bundleIdentifier, "com.example.app")
        XCTAssertEqual(SwiftKit.shared.deviceInfo.appName, "Example App")
        XCTAssertTrue(SwiftKit.shared.deviceInfo.isSimulator)
        XCTAssertTrue(SwiftKit.shared.deviceInfo.isDebugBuild)
    }

    private func makeBundle(info: [String: Any]) -> Bundle {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let bundleURL = directory.appendingPathComponent("Test.bundle")
        try? FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        let infoURL = bundleURL.appendingPathComponent("Info.plist")
        let data = try? PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try? data?.write(to: infoURL)
        return Bundle(url: bundleURL) ?? .main
    }
}
