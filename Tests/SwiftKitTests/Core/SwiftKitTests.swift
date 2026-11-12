import XCTest
@testable import SwiftKit

final class SwiftKitTests: XCTestCase {
    override func setUp() {
        super.setUp()
        SwiftKit.resetForTesting()
    }

    override func tearDown() {
        SwiftKit.resetForTesting()
        super.tearDown()
    }

    func testSDKInitializationLifecycle() throws {
        XCTAssertFalse(SwiftKit.isInitialized)

        let config = SwiftKitConfiguration(
            environment: .development,
            subsystem: "com.swiftkit.test",
            category: "CoreTests"
        )

        try SwiftKit.initialize(configuration: config)

        XCTAssertTrue(SwiftKit.isInitialized)
        XCTAssertNotNil(SwiftKit.shared)
        XCTAssertEqual(SwiftKit.shared.configuration.environment, .development)
        XCTAssertNotNil(SwiftKit.shared.logger)
    }

    func testDoubleInitializationThrowsError() throws {
        let config = SwiftKitConfiguration(environment: .development)

        try SwiftKit.initialize(configuration: config)

        XCTAssertThrowsError(try SwiftKit.initialize(configuration: config)) { error in
            XCTAssertEqual(error as? SDKError, .alreadyInitialized)
        }
    }

    func testResetForTesting() throws {
        let config = SwiftKitConfiguration(environment: .development)

        try SwiftKit.initialize(configuration: config)
        XCTAssertTrue(SwiftKit.isInitialized)

        SwiftKit.resetForTesting()
        XCTAssertFalse(SwiftKit.isInitialized)
    }
}
