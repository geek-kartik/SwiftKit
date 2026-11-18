import Foundation

/// Public contract for issuing HTTP requests.
///
/// The client normalizes transport errors into ``NetworkError``, validates status codes against
/// ``NetworkConfiguration/acceptableStatusCodes``, and returns decoded values through the
/// convenience methods. Implementations must be safe to call from any concurrency domain.
public protocol NetworkClientProtocol: Sendable {
    /// The configuration applied to outgoing requests.
    var configuration: NetworkConfiguration { get }

    /// Sends a request and returns the raw response.
    ///
    /// A response is returned only when its status code is accepted by
    /// ``NetworkConfiguration/acceptableStatusCodes``. Other status codes throw
    /// ``NetworkError/httpStatus(_:)`` with the response attached.
    /// - Parameter request: The request to send.
    /// - Returns: The accepted HTTP response.
    /// - Throws: A ``NetworkError`` describing transport, validation, or status failures.
    func send(_ request: NetworkRequest) async throws -> NetworkResponse
}

public extension NetworkClientProtocol {
    /// Sends a request and decodes the JSON response body.
    /// - Parameters:
    ///   - request: The request to send.
    ///   - type: The expected decoded response type.
    /// - Returns: The decoded response value.
    /// - Throws: A ``NetworkError`` describing transport, validation, status, or decoding failures.
    func send<Response: Decodable & Sendable>(
        _ request: NetworkRequest,
        as type: Response.Type
    ) async throws -> Response {
        let response = try await send(request)

        do {
            return try response.decode(type, using: configuration.decoderFactory())
        } catch let error as NetworkError {
            await notifyDecodingFailure(error, request: request, response: response)
            throw error
        }
    }

    /// Sends a request whose body is the JSON encoding of the supplied value.
    /// - Parameters:
    ///   - request: The base request. Its method, headers, and timeout are preserved.
    ///   - body: The encodable body to serialize using ``NetworkConfiguration/encoderFactory``.
    /// - Returns: The accepted HTTP response.
    /// - Throws: A ``NetworkError`` describing encoding, transport, validation, or status failures.
    func send<Body: Encodable & Sendable>(
        _ request: NetworkRequest,
        json body: Body
    ) async throws -> NetworkResponse {
        let request = try request.withJSONBody(body, using: configuration.encoderFactory())
        return try await send(request)
    }

    /// Sends a request with a JSON-encoded body and decodes the JSON response.
    /// - Parameters:
    ///   - request: The base request. Its method, headers, and timeout are preserved.
    ///   - body: The encodable body to serialize using ``NetworkConfiguration/encoderFactory``.
    ///   - type: The expected decoded response type.
    /// - Returns: The decoded response value.
    /// - Throws: A ``NetworkError`` describing encoding, transport, validation, status, or decoding failures.
    func send<Body: Encodable & Sendable, Response: Decodable & Sendable>(
        _ request: NetworkRequest,
        json body: Body,
        as type: Response.Type
    ) async throws -> Response {
        let response = try await send(request, json: body)

        do {
            return try response.decode(type, using: configuration.decoderFactory())
        } catch let error as NetworkError {
            await notifyDecodingFailure(error, request: request, response: response)
            throw error
        }
    }

    /// Notifies error callbacks when an accepted HTTP response fails to decode.
    ///
    /// Decoding happens outside the transport client, so this synthesizes the transaction from
    /// the resolved response URL, merged headers, and the original body.
    private func notifyDecodingFailure(
        _ error: NetworkError,
        request: NetworkRequest,
        response: NetworkResponse
    ) async {
        guard configuration.onError != nil || configuration.onAuthenticationFailure != nil else {
            return
        }

        var headers = configuration.defaultHeaders
        for (name, value) in request.headers {
            headers[name] = value
        }

        let transaction = NetworkTransaction(
            startedAt: Date(),
            duration: 0,
            request: NetworkTransaction.Request(
                method: request.method,
                url: response.url ?? request.url,
                headers: headers,
                body: request.body.map { NetworkTransaction.Body(data: $0) }
            ),
            response: NetworkTransaction.Response(
                statusCode: response.statusCode,
                headers: response.headers,
                body: NetworkTransaction.Body(data: response.data)
            ),
            error: error
        )

        await configuration.notify(transaction: transaction)
    }
}
