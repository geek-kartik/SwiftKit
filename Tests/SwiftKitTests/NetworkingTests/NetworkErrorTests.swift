import XCTest
@testable import SwiftKit

final class NetworkErrorTests: XCTestCase {
    private let response = NetworkResponse(
        statusCode: 422,
        headers: ["Content-Type": "application/json"],
        data: Data(#"{"error":"invalid_account"}"#.utf8)
    )

    func testAllCasesHaveDescriptions() {
        let errors: [NetworkError] = [
            .invalidURL,
            .invalidConfiguration(reason: "bad timeout"),
            .invalidRequest(reason: "body not allowed"),
            .invalidResponse,
            .transportFailure(code: .cannotConnectToHost),
            .timeout,
            .cancelled,
            .noInternetConnection,
            .emptyResponse,
            .encodingFailed,
            .decodingFailed,
            .httpStatus(response)
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertFalse(error.errorDescription?.isEmpty ?? true)
        }
    }

    func testHTTPStatusExposesResponseAndStatusCode() {
        let error = NetworkError.httpStatus(response)

        XCTAssertEqual(error.statusCode, 422)
        XCTAssertEqual(error.response, response)
    }

    func testNonHTTPErrorHasNoResponseOrStatusCode() {
        XCTAssertNil(NetworkError.timeout.response)
        XCTAssertNil(NetworkError.timeout.statusCode)
    }

    func testAuthenticationFailureForUnauthorizedAndForbidden() {
        XCTAssertTrue(NetworkError.httpStatus(makeResponse(statusCode: 401)).isAuthenticationFailure)
        XCTAssertTrue(NetworkError.httpStatus(makeResponse(statusCode: 403)).isAuthenticationFailure)
        XCTAssertFalse(NetworkError.httpStatus(makeResponse(statusCode: 400)).isAuthenticationFailure)
        XCTAssertFalse(NetworkError.timeout.isAuthenticationFailure)
    }

    func testRetryableHTTPStatusCodes() {
        for statusCode in [408, 425, 429, 500, 502, 503, 599] {
            XCTAssertTrue(
                NetworkError.httpStatus(makeResponse(statusCode: statusCode)).isRetryable,
                "Expected \(statusCode) to be retryable."
            )
        }

        for statusCode in [400, 401, 403, 404, 409, 422] {
            XCTAssertFalse(
                NetworkError.httpStatus(makeResponse(statusCode: statusCode)).isRetryable,
                "Expected \(statusCode) not to be retryable."
            )
        }
    }

    func testRetryableTransportErrors() {
        XCTAssertTrue(NetworkError.timeout.isRetryable)
        XCTAssertTrue(NetworkError.noInternetConnection.isRetryable)
        XCTAssertTrue(NetworkError.transportFailure(code: .timedOut).isRetryable)
        XCTAssertTrue(NetworkError.transportFailure(code: .networkConnectionLost).isRetryable)
        XCTAssertTrue(NetworkError.transportFailure(code: .dnsLookupFailed).isRetryable)
        XCTAssertTrue(NetworkError.transportFailure(code: .cannotConnectToHost).isRetryable)
    }

    func testNonRetryableErrors() {
        XCTAssertFalse(NetworkError.cancelled.isRetryable)
        XCTAssertFalse(NetworkError.decodingFailed.isRetryable)
        XCTAssertFalse(NetworkError.encodingFailed.isRetryable)
        XCTAssertFalse(NetworkError.invalidURL.isRetryable)
        XCTAssertFalse(NetworkError.invalidRequest(reason: "bad").isRetryable)
        XCTAssertFalse(NetworkError.invalidResponse.isRetryable)
        XCTAssertFalse(NetworkError.emptyResponse.isRetryable)
        XCTAssertFalse(NetworkError.transportFailure(code: .badURL).isRetryable)
    }

    // MARK: - Normalization

    func testNormalizationMapsCancelled() {
        XCTAssertEqual(NetworkError.normalized(from: URLError(.cancelled)), .cancelled)
    }

    func testNormalizationMapsTimedOut() {
        XCTAssertEqual(NetworkError.normalized(from: URLError(.timedOut)), .timeout)
    }

    func testNormalizationMapsOfflineErrors() {
        let codes: [URLError.Code] = [
            .notConnectedToInternet,
            .networkConnectionLost,
            .internationalRoamingOff,
            .dataNotAllowed
        ]

        for code in codes {
            XCTAssertEqual(NetworkError.normalized(from: URLError(code)), .noInternetConnection)
        }
    }

    func testNormalizationMapsBadURL() {
        XCTAssertEqual(NetworkError.normalized(from: URLError(.badURL)), .invalidURL)
        XCTAssertEqual(NetworkError.normalized(from: URLError(.unsupportedURL)), .invalidURL)
    }

    func testNormalizationMapsUnmappedURLErrorToTransportFailure() {
        XCTAssertEqual(
            NetworkError.normalized(from: URLError(.cannotConnectToHost)),
            .transportFailure(code: .cannotConnectToHost)
        )
        XCTAssertEqual(
            NetworkError.normalized(from: URLError(.secureConnectionFailed)),
            .transportFailure(code: .secureConnectionFailed)
        )
    }

    func testNormalizationMapsCancellationError() {
        XCTAssertEqual(NetworkError.normalized(from: CancellationError()), .cancelled)
    }

    func testNormalizationMapsUnknownNonURLError() {
        let error = NSError(domain: "Test", code: 1)

        XCTAssertEqual(NetworkError.normalized(from: error), .transportFailure(code: .unknown))
    }

    func testNormalizationPassesThroughNetworkError() {
        XCTAssertEqual(NetworkError.normalized(from: NetworkError.httpStatus(response)), .httpStatus(response))
    }

    func testLogDescriptionOmitsSensitiveAssociatedValues() {
        let errors: [NetworkError] = [
            .invalidConfiguration(reason: "secret-configuration"),
            .invalidRequest(reason: "secret-request"),
            .transportFailure(code: .cannotConnectToHost),
            .httpStatus(response)
        ]

        for error in errors {
            XCTAssertFalse(error.logDescription.contains("secret"))
            XCTAssertFalse(error.logDescription.contains("invalid_account"))
        }
    }

    private func makeResponse(statusCode: Int) -> NetworkResponse {
        NetworkResponse(statusCode: statusCode, data: Data())
    }
}
