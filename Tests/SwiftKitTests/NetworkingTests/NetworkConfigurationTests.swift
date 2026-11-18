import XCTest
@testable import SwiftKit

final class NetworkConfigurationTests: XCTestCase {
    func testDefaultConfigurationValues() {
        let configuration = NetworkConfiguration.default

        XCTAssertNil(configuration.baseURL)
        XCTAssertTrue(configuration.defaultHeaders.isEmpty)
        XCTAssertEqual(configuration.timeoutInterval, 30)
        XCTAssertEqual(configuration.acceptableStatusCodes, 200..<300)
        XCTAssertEqual(configuration.cachePolicy, .reloadIgnoringLocalCacheData)
    }

    func testCustomConfigurationValues() {
        let baseURL = URL(string: "https://api.bank.example/v1")!
        let configuration = NetworkConfiguration(
            baseURL: baseURL,
            defaultHeaders: ["Accept": "application/json"],
            timeoutInterval: 15,
            acceptableStatusCodes: 200..<300,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData
        )

        XCTAssertEqual(configuration.baseURL, baseURL)
        XCTAssertEqual(configuration.defaultHeaders["Accept"], "application/json")
        XCTAssertEqual(configuration.timeoutInterval, 15)
        XCTAssertEqual(configuration.acceptableStatusCodes, 200..<300)
        XCTAssertEqual(configuration.cachePolicy, .reloadIgnoringLocalAndRemoteCacheData)
    }

    func testValidateAcceptsValidConfiguration() {
        let configuration = NetworkConfiguration(
            baseURL: URL(string: "https://api.bank.example")!,
            timeoutInterval: 30,
            acceptableStatusCodes: 200..<300
        )

        XCTAssertNoThrow(try configuration.validate())
    }

    func testValidateAcceptsConfigurationWithoutBaseURL() {
        XCTAssertNoThrow(try NetworkConfiguration().validate())
    }

    func testValidateRejectsRelativeBaseURL() {
        let configuration = NetworkConfiguration(baseURL: URL(string: "/api")!)

        XCTAssertThrowsError(try configuration.validate()) { error in
            guard case NetworkError.invalidConfiguration(let reason) = error else {
                return XCTFail("Expected invalidConfiguration, got \(error)")
            }
            XCTAssertTrue(reason.contains("absolute"))
        }
    }

    func testValidateRejectsUnsupportedBaseURLScheme() {
        let configuration = NetworkConfiguration(baseURL: URL(string: "ftp://files.bank.example")!)

        XCTAssertThrowsError(try configuration.validate()) { error in
            guard case NetworkError.invalidConfiguration(let reason) = error else {
                return XCTFail("Expected invalidConfiguration, got \(error)")
            }
            XCTAssertTrue(reason.contains("http"))
        }
    }

    func testValidateRejectsZeroTimeout() {
        let configuration = NetworkConfiguration(timeoutInterval: 0)

        XCTAssertThrowsError(try configuration.validate()) { error in
            guard case NetworkError.invalidConfiguration(let reason) = error else {
                return XCTFail("Expected invalidConfiguration, got \(error)")
            }
            XCTAssertTrue(reason.contains("timeoutInterval"))
        }
    }

    func testValidateRejectsNegativeTimeout() {
        let configuration = NetworkConfiguration(timeoutInterval: -5)

        XCTAssertThrowsError(try configuration.validate())
    }

    func testValidateRejectsInfiniteTimeout() {
        let configuration = NetworkConfiguration(timeoutInterval: .infinity)

        XCTAssertThrowsError(try configuration.validate())
    }

    func testValidateRejectsEmptyStatusRange() {
        let configuration = NetworkConfiguration(acceptableStatusCodes: 200..<200)

        XCTAssertThrowsError(try configuration.validate()) { error in
            guard case NetworkError.invalidConfiguration(let reason) = error else {
                return XCTFail("Expected invalidConfiguration, got \(error)")
            }
            XCTAssertTrue(reason.contains("empty"))
        }
    }

    func testValidateRejectsStatusRangeBelowHTTPRange() {
        let configuration = NetworkConfiguration(acceptableStatusCodes: 99..<300)

        XCTAssertThrowsError(try configuration.validate())
    }

    func testValidateRejectsStatusRangeAboveHTTPRange() {
        let configuration = NetworkConfiguration(acceptableStatusCodes: 200..<601)

        XCTAssertThrowsError(try configuration.validate())
    }

    func testDecoderFactoryProducesFreshInstances() {
        let configuration = NetworkConfiguration()
        let first = configuration.decoderFactory()
        let second = configuration.decoderFactory()

        XCTAssertFalse(first === second)
    }

    func testEncoderFactoryProducesFreshInstances() {
        let configuration = NetworkConfiguration()
        let first = configuration.encoderFactory()
        let second = configuration.encoderFactory()

        XCTAssertFalse(first === second)
    }

    func testCustomDecoderFactoryIsUsed() throws {
        let configuration = NetworkConfiguration(decoderFactory: {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return decoder
        })

        let value = try configuration.decoderFactory().decode(
            SnakeCaseValue.self,
            from: Data(#"{"display_name":"Archana"}"#.utf8)
        )

        XCTAssertEqual(value.displayName, "Archana")
    }
}

private struct SnakeCaseValue: Decodable {
    let displayName: String
}
