# Networking Module

## Purpose & Scope
Provides a centralized HTTP layer for banking API requests and responses. The module supports
`GET`, `POST`, `PUT`, `PATCH`, and `DELETE`, per-request and default headers, JSON encoding and
decoding, configurable accepted status codes, request timeouts, cache policies, and standardized
error handling through a single `NetworkError` domain.

The module exposes a protocol (`NetworkClientProtocol`) so client applications and other SDK
modules never depend on the concrete `URLSession` implementation.

## Apple Frameworks
- `Foundation` (`URLSession`, `URLRequest`, `URLResponse`, `HTTPURLResponse`, `JSONEncoder`, `JSONDecoder`)

## Architecture
- `Public/NetworkClientProtocol.swift`: Public request contract plus decoded and JSON convenience methods.
- `Public/NetworkRequest.swift`: Immutable request value with absolute/relative URL support and JSON body helpers.
- `Public/NetworkResponse.swift`: Immutable response value with case-insensitive header lookup and JSON decoding.
- `Public/NetworkError.swift`: Standardized, `Sendable` networking errors and retry/auth helpers.
- `Public/HTTPMethod.swift`: Supported HTTP verbs.
- `Models/NetworkConfiguration.swift`: Base URL, default headers, timeout, accepted status range, cache policy, and coder factories.
- `Internal/HTTPTransport.swift`: Internal `URLSession` abstraction used for headless testing.
- `Internal/URLSessionNetworkClient.swift`: Concrete `NetworkClientProtocol` implementation with request construction, validation, logging, and status handling.

The client is constructed by `SDKDependencyContainer` and exposed through
`SwiftKit.shared.networkClient`.

## Configuration
`SwiftKitConfiguration` accepts a `NetworkConfiguration`:

```swift
import SwiftKit

let network = NetworkConfiguration(
    baseURL: URL(string: "https://api.bank.example")!,
    defaultHeaders: [
        "Accept": "application/json",
        "X-Client-Version": "2.4.0"
    ],
    timeoutInterval: 30,
    acceptableStatusCodes: 200..<300,
    cachePolicy: .reloadIgnoringLocalCacheData
)

let configuration = SwiftKitConfiguration(
    environment: .development,
    network: network
)

try SwiftKit.initialize(configuration: configuration)
```

### Configuration reference
| Option | Default | Description |
|---|---|---|
| `baseURL` | `nil` | Base URL for relative request paths. Must be an absolute HTTP(S) URL when supplied. |
| `defaultHeaders` | `[:]` | Headers applied to every request. Request headers override them case-insensitively. |
| `timeoutInterval` | `30` | Default request timeout in seconds. Must be finite and greater than zero. |
| `acceptableStatusCodes` | `200..<300` | Half-open range of status codes returned as responses. Others throw `.httpStatus`. |
| `cachePolicy` | `.reloadIgnoringLocalCacheData` | Default request cache policy. Banking responses should not be reused from the local cache. |
| `decoderFactory` | `{ JSONDecoder() }` | Creates a fresh decoder per decoded response. Use for snake_case or date strategies. |
| `encoderFactory` | `{ JSONEncoder() }` | Creates a fresh encoder per JSON request body. |

Coders are created per operation because `JSONEncoder` and `JSONDecoder` are not thread-safe and
must not be shared across concurrent requests.

`NetworkConfiguration.validate()` rejects invalid base URLs, non-positive timeouts, and empty or
out-of-range status intervals. `SwiftKit.initialize(configuration:)` validates the network
configuration as part of SDK startup.

## Usage

### GET with a decoded response
```swift
let account: Account = try await SwiftKit.shared.networkClient.send(
    try NetworkRequest(path: "/v1/accounts/acc_1"),
    as: Account.self
)
```

### GET with query parameters
```swift
let request = try NetworkRequest(
    path: "/v1/transactions",
    queryItems: [
        URLQueryItem(name: "page", value: "2"),
        URLQueryItem(name: "limit", value: "50")
    ],
    headers: ["Authorization": "Bearer \(accessToken)"]
)

let transactions = try await SwiftKit.shared.networkClient.send(
    request,
    as: [Transaction].self
)
```

### POST with a JSON body and decoded response
```swift
struct TransferRequest: Encodable {
    let fromAccount: String
    let toAccount: String
    let amount: Decimal
}

let request = try NetworkRequest(
    path: "/v1/transfers",
    method: .post,
    headers: ["Authorization": "Bearer \(accessToken)"]
)

let transfer = try await SwiftKit.shared.networkClient.send(
    request,
    json: TransferRequest(fromAccount: "acc_1", toAccount: "acc_2", amount: 250),
    as: Transfer.self
)
```

`withJSONBody` and the `send(_:json:)` conveniences set `Content-Type: application/json` unless a
content type is already present. To encode a body ahead of time, use
`NetworkRequest.withJSONBody(_:using:)`.

### Raw response access
```swift
let response = try await SwiftKit.shared.networkClient.send(request)
let body = response.data
let requestID = response.header(named: "x-request-id")
```

### PUT, PATCH, DELETE
```swift
try await SwiftKit.shared.networkClient.send(
    NetworkRequest(url: profileUpdateURL, method: .patch, body: patchData)
)

_ = try await SwiftKit.shared.networkClient.send(
    try NetworkRequest(path: "/v1/accounts/acc_1", method: .delete)
)
```

### Custom JSON strategies
```swift
let network = NetworkConfiguration(
    baseURL: URL(string: "https://api.bank.example")!,
    decoderFactory: {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    },
    encoderFactory: {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }
)
```

## URL Resolution
- A request URL with a scheme is used as-is and must use `http` or `https`.
- A relative URL (created from `NetworkRequest(path:)`) is appended to `baseURL`, preserving the
  base URL's path prefix. For example, base `https://api.bank.example/api/v1` plus `/accounts`
  resolves to `https://api.bank.example/api/v1/accounts`.
- A relative URL without a configured `baseURL` throws `NetworkError.invalidURL`.

## Status Code Handling
`send` returns raw and decoded responses only when the status code is inside
`acceptableStatusCodes` (default `200..<300`). All other status codes throw
`NetworkError.httpStatus(response)`, preserving the status code, headers, and raw body so the
caller can decode the bank's error payload:

```swift
do {
    let transfer = try await client.send(request, as: Transfer.self)
} catch let error as NetworkError {
    if case .httpStatus(let response) = error {
        let apiError = try? response.decode(BankAPIError.self)
        switch response.statusCode {
        case 401, 403:
            // Re-authenticate or present an authorization message.
        case 422:
            // Present validation feedback from apiError.
        default:
            break
        }
    }
}
```

## Error Handling
| Error | Meaning | Retryable |
|---|---|---|
| `.invalidURL` | Malformed URL, unsupported scheme, or unresolved relative path | No |
| `.invalidConfiguration` | Invalid timeout, accepted status range, or base URL | No |
| `.invalidRequest` | Invalid request, such as a body on `GET` | No |
| `.invalidResponse` | The system returned a non-HTTP response | No |
| `.transportFailure(code:)` | Unmapped `URLError` failure | Depends on the code |
| `.timeout` | The request exceeded its timeout | Yes |
| `.noInternetConnection` | Offline, connection lost, or data restricted | Yes |
| `.emptyResponse` | Decoding was requested but the body was empty | No |
| `.encodingFailed` | The request body could not be JSON-encoded | No |
| `.decodingFailed` | The response body could not be JSON-decoded | No |
| `.httpStatus` | The server returned an unaccepted status code | `408`, `425`, `429`, `5xx` |

Helpers are provided for common decisions:
- `isRetryable` identifies transient transport and server failures.
- `isAuthenticationFailure` identifies `401` and `403`.
- `statusCode` and `response` expose the attached HTTP response for `.httpStatus`.

Retries are intentionally not automatic. Callers must ensure a request is idempotent before
retrying.

## Security & Privacy
- Request and response payloads, headers, URL paths, and query strings are never logged.
- Diagnostics include only the HTTP method, host, status code, elapsed time, and a redacted error
  category.
- The default cache policy avoids reusing banking responses from the local HTTP cache.
- The ephemeral `URLSession` avoids persistent disk caches and cookie storage unless the host
  application configures otherwise.
- Authentication headers and tokens should be read from `SecureStorageProtocol`, never hardcoded.
- Always use HTTPS; HTTP connections are blocked by App Transport Security in production builds.

## Threading
- `URLSessionNetworkClient` and `NetworkConfiguration` are `Sendable`.
- Requests are executed with `async/await` and may be issued concurrently.
- JSON encoder and decoder instances are created per operation through the configured factories.
- The internal `URLSession` transport is thread-safe and guarded by Foundation's own synchronization.
- No mutable shared state is held by the client.

## Testing
- Unit tests inject an internal `HTTPTransport` double, so request construction, header merging,
  status handling, error mapping, and logging are verified without network access.
- A `URLProtocol` stub verifies the real `URLSessionTransport` end to end.
- Tests cover every HTTP method, absolute and relative URL resolution, headers, timeouts, cache
  policies, JSON encoding/decoding, all accepted and rejected status classes, transport error
  mapping, cancellation, logging redaction, concurrency, and facade wiring.

```bash
swift test --filter Network
```
