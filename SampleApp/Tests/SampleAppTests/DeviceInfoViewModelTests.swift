import XCTest
import SwiftKit
@testable import SampleApp

@MainActor
final class DeviceInfoViewModelTests: XCTestCase {
    private var mockDeviceInfo: MockDeviceInfo!
    private var mockLogger: MockLogger!
    private var viewModel: DeviceInfoViewModel!

    override func setUp() {
        super.setUp()
        mockDeviceInfo = MockDeviceInfo()
        mockLogger = MockLogger()
        viewModel = DeviceInfoViewModel(deviceInfo: mockDeviceInfo, logger: mockLogger)
    }

    override func tearDown() {
        viewModel = nil
        mockDeviceInfo = nil
        mockLogger = nil
        super.tearDown()
    }

    func testLoadDeviceInfoPopulatesProperties() {
        XCTAssertEqual(viewModel.deviceModel, "iPhone15,2")
        XCTAssertEqual(viewModel.osVersion, "17.4")
        XCTAssertEqual(viewModel.appVersion, "1.2.0")
        XCTAssertEqual(viewModel.buildNumber, "42")
        XCTAssertEqual(viewModel.bundleIdentifier, "com.swiftkit.sampleapp")
        XCTAssertEqual(viewModel.appName, "SampleApp")
        XCTAssertTrue(viewModel.isSimulator)
        XCTAssertTrue(viewModel.isDebugBuild)
    }

    func testAppVersionComparisonLogic() {
        // App version is "1.2.0"
        viewModel.comparisonTargetVersion = "1.0.0"
        viewModel.evaluateAppVersion()
        XCTAssertTrue(viewModel.isAppVersionAtLeastResult)
        XCTAssertFalse(viewModel.isUpdateRequiredResult)

        viewModel.comparisonTargetVersion = "2.0.0"
        viewModel.evaluateAppVersion()
        XCTAssertFalse(viewModel.isAppVersionAtLeastResult)
        XCTAssertTrue(viewModel.isUpdateRequiredResult)
    }

    func testOSVersionComparisonLogic() {
        // OS version is "17.4"
        viewModel.osComparisonTargetVersion = "17.0"
        viewModel.evaluateOSVersion()
        XCTAssertTrue(viewModel.isOSVersionAtLeastResult)

        viewModel.osComparisonTargetVersion = "18.0"
        viewModel.evaluateOSVersion()
        XCTAssertFalse(viewModel.isOSVersionAtLeastResult)
    }
}
