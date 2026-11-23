# Networking Module

Async HTTP client built on `URLSession`. It supports `GET`, `POST`, `PUT`, `PATCH`, and `DELETE`, absolute or base-relative URLs, header merging, JSON encoding/decoding, per-request timeouts and cache policies, and one `NetworkError` domain. Clients depend on `NetworkClientProtocol`, not the concrete transport.

## Public API

```swift
public protocol NetworkClientProtocol: Sendable {
    var configuration: NetworkConfiguration { get }
    func send(_ request: NetworkRequest) async throws -> NetworkResponse
}
```

Default protocol methods add:

- `send(_:as:)` — decode a JSON response to a `Decodable & Sendable` type.
- `send(_:json:)` — encode a JSON request body with the configured encoder factory.
- `send(_:json:as:)` — encode the body and decode the response.

Supporting types: `NetworkRequest` (immutable builder), `NetworkResponse` (status, headers, data, `decode(_:using:)`), `NetworkError`, `HTTPMethod` (`.get`, `.post`, `.put`, `.patch`, `.delete`), and `NetworkTransaction` (diagnostic record passed to error callbacks, with `curlCommand` helpers).

## Configuration

```swift
let network = NetworkConfiguration(
    baseURL: URL(string: "https://api.example.com")!,
    defaultHeaders: ["Accept": "application/json"],
    tokenProvider: { SwiftKit.shared.session.currentSession?.accessToken }
)

let configuration = SwiftKitConfiguration(environment: .development, network: network)
try SwiftKit.initialize(configuration: configuration)
```

| Option | Default | Description |
|---|---|---|
| `baseURL` | `nil` | Base for relative request paths; an absolute HTTP(S) URL with host when set. |
| `defaultHeaders` | `[:]` | Applied to every request; request headers win on case-insensitive matches. |
| `timeoutInterval` | `30` | Default timeout in seconds; must be finite and greater than zero. |
| `acceptableStatusCodes` | `200..<300` | Statuses returned as responses; others throw `.httpStatus`. |
| `cachePolicy` | `.reloadIgnoringLocalCacheData` | Default request cache policy. |
| `tokenProvider` | `nil` | Async closure supplying a bearer token added to outgoing requests. |
| `sessionConfigurationFactory` | `nil` | Returns the `URLSessionConfiguration` for the client; use it to register `URLProtocol` stubs or a proxy. `nil` uses an ephemeral configuration. |
| `onError` | `nil` | Async callback for failed transactions. |
| `onAuthenticationFailure` | `nil` | Async callback for `401`/`403`, in addition to `onError`. |
| `decoderFactory` / `encoderFactory` | New `JSONDecoder()` / `JSONEncoder()` | Called per operation; Foundation coders are not thread-safe. |

`SwiftKit.initialize(configuration:)` calls `NetworkConfiguration.validate()`, which rejects invalid base URLs, non-positive timeouts, and empty or out-of-range status ranges.

`NetworkConfiguration.refreshToken` and `logErrorDetails` exist as stored properties but are not invoked by the client. Use `onAuthenticationFailure` for auth handling, and handle refresh/retry in your app.

## Usage

### GET with a decoded response

```swift
struct Account: Decodable, Sendable {
    let id: String
    let name: String
}

let account: Account = try await SwiftKit.shared.networkClient.send(
    try NetworkRequest(path: "/v1/accounts/acc_1"),
    as: Account.self
)
```

### Query parameters and headers

```swift
let request = try NetworkRequest(
    path: "/v1/transactions",
    queryItems: [
        URLQueryItem(name: "page", value: "2"),
        URLQueryItem(name: "limit", value: "50")
    ],
    headers: ["X-Request-ID": "abc-123"]
)

let accounts = try await SwiftKit.shared.networkClient.send(
    request,
    as: [Account].self
)
```

### POST with JSON

```swift
struct Transfer: Encodable, Sendable {
    let fromAccount: String
    let toAccount: String
    let amount: Decimal
}

struct TransferConfirmation: Decodable, Sendable {
    let id: String
}

let created = try await SwiftKit.shared.networkClient.send(
    try NetworkRequest(path: "/v1/transfers", method: .post),
    json: Transfer(fromAccount: "acc_1", toAccount: "acc_2", amount: 250),
    as: TransferConfirmation.self
)
```

`send(_:json:)` and `NetworkRequest.withJSONBody(_:using:)` set `Content-Type: application/json` unless a content type is already present.

### Raw response and other methods

```swift
let response = try await SwiftKit.shared.networkClient.send(request)
let body = response.data
let requestID = response.header(named: "x-request-id")

try await SwiftKit.shared.networkClient.send(
    NetworkRequest(url: profileURL, method: .patch, body: patchData)
)
try await SwiftKit.shared.networkClient.send(
    try NetworkRequest(path: "/v1/accounts/acc_1", method: .delete)
)
```

A body on a `GET` request is rejected with `.invalidRequest`.

### Custom JSON strategies

```swift
let network = NetworkConfiguration(
    baseURL: URL(string: "https://api.example.com")!,
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

### Custom URL session

```swift
let network = NetworkConfiguration(
    baseURL: URL(string: "https://sample.swiftkit.test"),
    sessionConfigurationFactory: {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SampleURLProtocol.self]
        return configuration
    }
)
```

The factory runs once when the client is created and must return a fresh configuration. The client applies `timeoutInterval` and `cachePolicy` and disables the URL cache on the returned value.

## URL resolution

- Absolute URLs are used as-is and must use `http` or `https`.
- Relative URLs are appended to `baseURL`, preserving its path prefix; base `https://api.example.com/api/v1` plus `/accounts` resolves to `https://api.example.com/api/v1/accounts`.
- A relative URL without `baseURL` throws `.invalidURL`.

## Error handling

`send` returns a response only when its status is accepted. Other statuses throw `NetworkError.httpStatus(response)` with status, headers, and body preserved for decoding a server error payload.

| Error | Meaning |
|---|---|
| `.invalidURL` | Malformed URL, unsupported scheme, or no base URL for a relative path |
| `.invalidConfiguration` | Invalid timeout, status range, or base URL |
| `.invalidRequest` | Invalid request, such as a body on `GET` |
| `.invalidResponse` | Non-HTTP response from the transport |
| `.transportFailure(code:)` | Unmapped `URLError` |
| `.timeout`, `.cancelled`, `.noInternetConnection` | Timeout, cancellation, or offline failure |
| `.emptyResponse`, `.encodingFailed`, `.decodingFailed` | Body encode/decode failures |
| `.httpStatus(response)` | Unaccepted HTTP status |

Helpers: `isRetryable` (transient transport and 408/425/429/5xx failures), `isAuthenticationFailure` (401/403), `statusCode`, and `response`. Retries are never automatic; callers must ensure idempotency.

`onError` runs for all failed transactions; `onAuthenticationFailure` also runs for 401/403. Both are awaited before the error is rethrown, so keep them fast. They report failures only — your app must perform sign-out or refresh.

```swift
let network = NetworkConfiguration(
    baseURL: URL(string: "https://api.example.com")!,
    onError: { transaction in
        print("Request failed: \(transaction.pathText), status \(transaction.statusCode.map(String.init) ?? "none")")
    },
    onAuthenticationFailure: { transaction in
        print("Authentication failed for \(transaction.pathText)")
    }
)
```

## Transactions and cURL

Failed requests produce a `NetworkTransaction` with the resolved URL, merged headers, request/response body data, status, duration, and normalized error. It can render a shell-pasteable command:

```swift
let redacted = transaction.curlCommand
let withHeaders = transaction.curlCommand(sensitiveDataPolicy: .include)
```

The default command replaces credential headers with `[REDACTED]`. Bodies are raw and uncapped in the transaction; do not log them directly — pass any sensitive text through `DataMasker` first. The networking client itself emits no request/response logs.

## Files and implementation notes

- `Public/`: `NetworkClientProtocol.swift`, `NetworkRequest.swift`, `NetworkResponse.swift`, `NetworkError.swift`, `NetworkTransaction.swift`, `HTTPMethod.swift`.
- `Models/NetworkConfiguration.swift`: immutable configuration and validation.
- `Internal/`: `HTTPTransport.swift` (injectable `URLSession` abstraction), `URLSessionNetworkClient.swift` (request construction and status handling), plus internal helpers.
- The client uses an ephemeral `URLSession` with no disk cache by default and is safe for concurrent requests. Supply `sessionConfigurationFactory` to customize the session (for example, to register a `URLProtocol` stub). There is no in-app network inspector, console request logging, automatic token refresh, or automatic retry.
- `NetworkConfiguration.LogVerbosity` is declared but not wired into request handling; do not rely on it.

## Testing

Tests inject an internal `HTTPTransport` double and use a `URLProtocol` stub, so request construction, status handling, error mapping, and concurrency are verified without external network access.

```bash
swift test --filter Network
```
