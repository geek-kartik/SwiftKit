import XCTest
@testable import SwiftKit

private final class MockDeviceInfo: DeviceInfoProtocol, Sendable {
    let deviceModel: String
    let osVersion: String
    let appVersion: String
    let buildNumber: String

    init(
        deviceModel: String,
        osVersion: String,
        appVersion: String,
        buildNumber: String
    ) {
        self.deviceModel = deviceModel
        self.osVersion = osVersion
        self.appVersion = appVersion
        self.buildNumber = buildNumber
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
    }

    func testEmptyBundleInfoUsesDefaults() {
        let bundle = makeBundle(info: [
            "CFBundleShortVersionString": "   ",
            "CFBundleVersion": ""
        ])

        let deviceInfo = SystemDeviceInfo(
            bundle: bundle,
            osVersion: "macOS 15.0",
            deviceModel: "arm64"
        )

        XCTAssertEqual(deviceInfo.appVersion, "0.0.0")
        XCTAssertEqual(deviceInfo.buildNumber, "0")
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
            buildNumber: "310"
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
