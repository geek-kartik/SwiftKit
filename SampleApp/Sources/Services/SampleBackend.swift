import Foundation
import SwiftKit

public extension Notification.Name {
    static let sampleNetworkError = Notification.Name("com.swiftkit.sampleapp.network.error")
    static let sampleNetworkAuthenticationFailure = Notification.Name("com.swiftkit.sampleapp.network.authenticationFailure")
}

public struct SampleAPIResponse: Codable, Sendable {
    public let status: String
    public let message: String
    public let method: String?
    public let path: String?
    public let authorized: Bool?
    public let accessToken: String?

    public init(
        status: String,
        message: String,
        method: String? = nil,
        path: String? = nil,
        authorized: Bool? = nil,
        accessToken: String? = nil
    ) {
        self.status = status
        self.message = message
        self.method = method
        self.path = path
        self.authorized = authorized
        self.accessToken = accessToken
    }
}

public struct SampleJSONBody: Codable, Sendable {
    public let message: String

    public init(message: String) {
        self.message = message
    }
}

public struct SampleRefreshRequest: Codable, Sendable {
    public let refreshToken: String

    public init(refreshToken: String) {
        self.refreshToken = refreshToken
    }
}

public struct SampleRefreshResponse: Codable, Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresIn: Int

    public init(accessToken: String, refreshToken: String, expiresIn: Int) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresIn = expiresIn
    }
}

public enum SampleBackendError: Error, LocalizedError, Equatable, Sendable {
    case invalidRefreshToken

    public var errorDescription: String? {
        switch self {
        case .invalidRefreshToken:
            return "The sample backend requires a non-empty refresh token."
        }
    }
}

public struct SampleBackendOutcome: Sendable {
    public let statusCode: Int
    public let data: Data

    public init(statusCode: Int, data: Data) {
        self.statusCode = statusCode
        self.data = data
    }
}

public actor SampleBackend {
    public static let shared = SampleBackend()

    private var tokenIsStale = true
    private var refreshCount = 0

    private init() {}

    public func refresh(refreshToken: String) throws -> SampleRefreshResponse {
        guard !refreshToken.isEmpty else {
            throw SampleBackendError.invalidRefreshToken
        }

        tokenIsStale = false
        refreshCount += 1

        return SampleRefreshResponse(
            accessToken: "sample_access_token_refreshed_\(refreshCount)",
            refreshToken: "sample_refresh_token_\(refreshCount + 1)",
            expiresIn: 3600
        )
    }

    public func markTokenStale() {
        tokenIsStale = true
    }

    public func reset() {
        tokenIsStale = true
        refreshCount = 0
    }

    public func handle(_ request: URLRequest) -> SampleBackendOutcome {
        let method = request.httpMethod ?? "GET"
        let path = request.url?.path ?? "/"
        let authorization = request.value(forHTTPHeaderField: "Authorization")

        if path == "/v1/auth/refresh" {
            return refreshOutcome(request: request)
        }

        if path == "/v1/protected" {
            guard !tokenIsStale, let authorization else {
                return unauthorized(path: path, method: method)
            }
            return success(
                SampleAPIResponse(
                    status: "ok",
                    message: "Protected resource loaded after refresh.",
                    method: method,
                    path: path,
                    authorized: true,
                    accessToken: DataMasker.mask(authorization)
                )
            )
        }

        switch path {
        case "/v1/failure":
            return SampleBackendOutcome(
                statusCode: 500,
                data: Data(#"{"status":"error","message":"Simulated server failure."}"#.utf8)
            )
        case "/v1/bad-json":
            return SampleBackendOutcome(statusCode: 200, data: Data("this is not json".utf8))
        case "/v1/not-found":
            return SampleBackendOutcome(
                statusCode: 404,
                data: Data(#"{"status":"error","message":"Resource not found."}"#.utf8)
            )
        default:
            guard path.hasPrefix("/v1/") else {
                return SampleBackendOutcome(
                    statusCode: 404,
                    data: Data(#"{"status":"error","message":"Unknown sample endpoint."}"#.utf8)
                )
            }

            let bodyMessage = message(from: request) ?? "No JSON body supplied."
            return success(
                SampleAPIResponse(
                    status: "ok",
                    message: "\(method) handled by SampleBackend. \(bodyMessage)",
                    method: method,
                    path: path,
                    authorized: authorization != nil
                )
            )
        }
    }

    private func refreshOutcome(request: URLRequest) -> SampleBackendOutcome {
        do {
            let body = bodyData(from: request) ?? Data()
            let payload = try JSONDecoder().decode(SampleRefreshRequest.self, from: body)
            let refreshed = try refresh(refreshToken: payload.refreshToken)
            let data = try JSONEncoder().encode(refreshed)
            return SampleBackendOutcome(statusCode: 200, data: data)
        } catch {
            return SampleBackendOutcome(
                statusCode: 400,
                data: Data(#"{"status":"error","message":"Refresh token rejected."}"#.utf8)
            )
        }
    }

    private func unauthorized(path: String, method: String) -> SampleBackendOutcome {
        SampleBackendOutcome(
            statusCode: 401,
            data: (try? JSONEncoder().encode(
                SampleAPIResponse(
                    status: "error",
                    message: "Access token expired for \(method) \(path).",
                    method: method,
                    path: path,
                    authorized: false
                )
            )) ?? Data()
        )
    }

    private func success(_ response: SampleAPIResponse) -> SampleBackendOutcome {
        SampleBackendOutcome(statusCode: 200, data: (try? JSONEncoder().encode(response)) ?? Data())
    }

    private func message(from request: URLRequest) -> String? {
        guard let body = bodyData(from: request) else {
            return nil
        }
        return try? JSONDecoder().decode(SampleJSONBody.self, from: body).message
    }

    private func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return nil
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while true {
            let count = stream.read(buffer, maxLength: bufferSize)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

public final class SampleURLProtocol: URLProtocol {
    private static let host = "sample.swiftkit.test"
    private var isCancelled = false

    public override class func canInit(with request: URLRequest) -> Bool {
        guard let url = request.url,
              let scheme = url.scheme?.lowercased(),
              scheme == "https",
              let host = url.host?.lowercased(),
              host == Self.host else {
            return false
        }
        return true
    }

    public override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    public override func startLoading() {
        let request = self.request
        Task { [weak self] in
            // Simulate realistic network latency so the loading state stays visible
            // instead of flickering for an instantly resolved mock response.
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let self, !self.isCancelled else { return }

            let outcome = await SampleBackend.shared.handle(request)
            guard let url = request.url else {
                return
            }

            let response = HTTPURLResponse(
                url: url,
                statusCode: outcome.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!

            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: outcome.data)
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }

    public override func stopLoading() {
        isCancelled = true
    }
}
