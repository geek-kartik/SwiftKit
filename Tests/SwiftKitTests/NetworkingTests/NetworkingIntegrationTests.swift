import XCTest
@testable import SwiftKit

private struct IntegrationAccount: Decodable, Equatable, Sendable {
    let identifier: String
}

final class NetworkingIntegrationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        SwiftKit.resetForTesting()
    }

    override func tearDown() {
        SwiftKit.resetForTesting()
        super.tearDown()
    }

    func testDefaultContainerProvidesNetworkClient() {
        let baseURL = URL(string: "https://api.bank.example")!
        let configuration = SwiftKitConfiguration(
            network: NetworkConfiguration(baseURL: baseURL, timeoutInterval: 20)
        )

        let container = SDKDependencyContainer(configuration: configuration)

        XCTAssertTrue(container.networkClient is URLSessionNetworkClient)
        XCTAssertEqual(container.networkClient.configuration.baseURL, baseURL)
        XCTAssertEqual(container.networkClient.configuration.timeoutInterval, 20)
    }

    func testFacadeExposesInjectedNetworkClient() async throws {
        let configuration = SwiftKitConfiguration(
            network: NetworkConfiguration(baseURL: URL(string: "https://api.bank.example")!)
        )
        let logger = MockLogger()
        let transport = MockHTTPTransport { request in
            (
                Data(#"{"identifier":"acc_1"}"#.utf8),
                makeHTTPResponse(url: request.url!, statusCode: 200)
            )
        }
        let networkClient = URLSessionNetworkClient(
            configuration: configuration.network,
            logger: logger,
            transport: transport
        )
        let container = SDKDependencyContainer(
            configuration: configuration,
            logger: logger,
            networkClient: networkClient
        )

        SwiftKit.initializeForTesting(container: container)

        XCTAssertTrue(SwiftKit.shared.networkClient as AnyObject === networkClient)

        let request = try NetworkRequest(path: "/v1/accounts/acc_1")
        let account = try await SwiftKit.shared.networkClient.send(
            request,
            as: IntegrationAccount.self
        )

        XCTAssertEqual(account, IntegrationAccount(identifier: "acc_1"))
        XCTAssertEqual(
            transport.lastRequest?.url?.absoluteString,
            "https://api.bank.example/v1/accounts/acc_1"
        )
    }

    func testInitializationSucceedsWithValidNetworkConfiguration() throws {
        let configuration = SwiftKitConfiguration(
            network: NetworkConfiguration(
                baseURL: URL(string: "https://api.bank.example")!,
                defaultHeaders: ["Accept": "application/json"],
                timeoutInterval: 25
            )
        )

        XCTAssertNoThrow(try SwiftKit.initialize(configuration: configuration))
        XCTAssertTrue(SwiftKit.shared.networkClient.configuration.defaultHeaders["Accept"] == "application/json")
    }

    func testInitializationFailsWithInvalidNetworkConfiguration() {
        let configuration = SwiftKitConfiguration(
            network: NetworkConfiguration(timeoutInterval: 0)
        )

        XCTAssertThrowsError(try SwiftKit.initialize(configuration: configuration)) { error in
            guard case SDKError.invalidConfiguration(let reason) = error else {
                return XCTFail("Expected invalidConfiguration, got \(error)")
            }
            XCTAssertTrue(reason.contains("network"))
            XCTAssertTrue(reason.contains("timeoutInterval"))
        }

        XCTAssertFalse(SwiftKit.isInitialized)
    }

    func testInitializationFailsWithInvalidNetworkBaseURL() {
        let configuration = SwiftKitConfiguration(
            network: NetworkConfiguration(baseURL: URL(string: "ftp://files.bank.example")!)
        )

        XCTAssertThrowsError(try SwiftKit.initialize(configuration: configuration)) { error in
            guard case SDKError.invalidConfiguration = error else {
                return XCTFail("Expected invalidConfiguration, got \(error)")
            }
        }
    }
}
