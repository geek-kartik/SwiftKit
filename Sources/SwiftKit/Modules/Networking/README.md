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
| `logVerbosity` | `.summary` | Networking diagnostics: `.off`, `.summary` (one line), or `.verbose` (full transaction block). |
| `maxLoggedBodyBytes` | `8_192` | Maximum request/response body bytes captured by verbose logs. `0` omits body content. |
| `inspector` | `.disabled` | Session inspector capture, retention limit, body cap, and redaction policy. |
| `onError` | `nil` | Async callback invoked for every failed transaction. |
| `onAuthenticationFailure` | `nil` | Async callback invoked for `401` and `403` failures. |
| `decoderFactory` | `{ JSONDecoder() }` | Creates a fresh decoder per decoded response. Use for snake_case or date strategies. |
| `encoderFactory` | `{ JSONEncoder() }` | Creates a fresh encoder per JSON request body. |

Coders are created per operation because `JSONEncoder` and `JSONDecoder` are not thread-safe and
must not be shared across concurrent requests.

`NetworkConfiguration.validate()` rejects invalid base URLs, non-positive timeouts, and empty or
out-of-range status intervals. `SwiftKit.initialize(configuration:)` validates the network
configuration as part of SDK startup.

## Session inspector

The SDK can capture every transaction and expose it as a searchable, in-app log with headers,
bodies, timing, and copy-as-cURL. Capture is opt-in and disabled by default.

```swift
let network = NetworkConfiguration(
    baseURL: URL(string: "https://api.bank.example")!,
    inspector: NetworkInspectorConfiguration(
        isEnabled: true,
        maxTransactions: 200,
        maxBodyBytes: 32_768,
        sensitiveDataPolicy: .redact
    )
)
```

Present the SDK-provided screen from any SwiftUI navigation container:

```swift
import SwiftKit
import SwiftUI

NavigationView {
    NetworkInspectorView(inspector: SwiftKit.shared.networkInspector)
}
```

| Option | Default | Description |
|---|---|---|
| `isEnabled` | `false` | Records transactions when `true`. |
| `maxTransactions` | `200` | Ring-buffer size. Oldest entries are evicted first. |
| `maxBodyBytes` | `32_768` | Per-body capture cap. Larger bodies are stored truncated and flagged. |
| `sensitiveDataPolicy` | `.redact` | `.redact` hides credentials; `.include` exports them verbatim. |

The history is also available without the UI:

```swift
let inspector = SwiftKit.shared.networkInspector

let newestFirst = inspector.transactions
let one = inspector.transaction(id: transactionID)

for await snapshot in inspector.updates() {
    render(snapshot)
}

inspector.clear()
```

What is captured:

- The fully resolved URL, including any query string.
- Merged headers, so configuration defaults are included.
- Raw request and response bodies, capped by `maxBodyBytes`.
- Status code, duration, and the normalized `NetworkError`.
- Failures that happen before the transport, such as `invalidURL` and `invalidRequest`.

Capture is in-memory only and resets when the process exits. Requests issued outside
`NetworkClientProtocol` are never captured.

### Floating overlay

`NetworkInspectorOverlay` adds a draggable circular trigger to every screen and presents the
inspector as a sheet:

```swift
RootView()
    .overlay {
        if let inspector = SwiftKit.shared.networkInspector {
            NetworkInspectorOverlay(inspector: inspector)
        }
    }
```

- Drag the button anywhere inside the safe area; its position persists across launches.
- Tap it to open the sheet, which lists transactions newest-first.
- Pass `initiallyPresented: true` to open the sheet at launch for automation.
- The overlay is opt-in. Attach it only in development builds.

### Copy as cURL

Every transaction can produce a shell-pasteable command:

```swift
let redacted = transaction.curlCommand
let replayable = transaction.curlCommand(sensitiveDataPolicy: .include)
```

```text
curl -X PATCH 'https://api.bank.example/v1/accounts/acc-1' \
  -H 'Accept: application/json' \
  -H 'Authorization: Bearer token' \
  -H 'Content-Type: application/json' \
  --data-raw '{"nickname":"Daily driver"}'
```

The command includes the method, resolved URL, every header, and the request body. Embedded
single quotes are escaped. Truncated or non-UTF-8 bodies add a leading shell comment instead of
producing a command that silently sends partial data.

With `.redact`, credential headers become `[REDACTED]`, so the command documents the request but
needs a fresh token before replay. Use `.include` only with local, non-production credentials.

## Global error callbacks

`NetworkConfiguration` accepts two async callbacks for cross-cutting handling:

```swift
let network = NetworkConfiguration(
    baseURL: URL(string: "https://api.bank.example")!,
    onError: { transaction in
        await telemetry.record(transaction)
    },
    onAuthenticationFailure: { transaction in
        await MainActor.run {
            session.signOut()
        }
    }
)
```

| Callback | Invoked for |
|---|---|
| `onError` | Every failed transaction: status, transport, validation, and decoding failures. |
| `onAuthenticationFailure` | `401` and `403` responses. `onError` also runs for these. |

Callbacks are awaited before the original error is rethrown, so session state is updated before
the calling screen handles the failure. Successful requests do not invoke either callback. A
slow handler delays the request's completion, so keep handlers fast and hand heavy work to
another task.

A `401` is not always a session expiry: sign-in and token-refresh endpoints also use `401` to
reject bad credentials. Inspect `transaction.request.url` before ending the session, for example
by skipping your authentication endpoint:

```swift
onAuthenticationFailure: { transaction in
    guard transaction.request.url.path != "/v1/auth/login" else { return }
    await MainActor.run { session.signOut() }
}
```

## Debugging in Xcode

Enable verbose diagnostics while developing to print one readable transaction block per request:

```swift
let network = NetworkConfiguration(
    baseURL: URL(string: "https://api.bank.example")!,
    logVerbosity: .verbose
)
```

```text
[HTTP] ┌─ POST https://api.bank.example/v1/transfers
[HTTP] │ Request headers
[HTTP] │   Accept: application/json
[HTTP] │   Authorization: [REDACTED]
[HTTP] │   Content-Type: application/json
[HTTP] │ Request body · 74 B
[HTTP] │   {
[HTTP] │     "amount" : 25.5,
[HTTP] │     "fromAccountId" : "acc-1001",
[HTTP] │     "toAccountId" : "acc-1002"
[HTTP] │   }
[HTTP] │ ← 201 Created · 38 ms · 96 B
[HTTP] │ Response headers
[HTTP] │   Content-Type: application/json; charset=utf-8
[HTTP] │ Response body · 96 B
[HTTP] │   {
[HTTP] │     "status" : "completed",
[HTTP] │     "transferId" : "trf-464C0F4F"
[HTTP] │   }
[HTTP] └─
```

To read it:

1. Run the app from Xcode (**⌘R**).
2. Show the debug console (**⌘⇧Y**).
3. Filter the console for `[HTTP]` to hide everything else.

Behaviour:

| Mode | Output |
|---|---|
| `.off` | Nothing, including send failures. |
| `.summary` | One line: `GET api.example.com -> 200 in 12 ms`. |
| `.verbose` | The block above, including failures and rejected statuses. |

Formatting guarantees:

- JSON bodies are pretty-printed without re-parsing values, so number literals stay byte-for-byte
  as they appeared on the wire; non-UTF-8 bodies render as `<binary N bytes>`.
- Long blocks are split into sub-1 KB chunks at line boundaries, because `os_log` truncates
  larger messages. No body content is lost to the system log limit.
- Bodies longer than `maxLoggedBodyBytes` are labelled with their total size and captured prefix.
- `Authorization`, `Proxy-Authorization`, `Cookie`, `Set-Cookie`, `X-Api-Key`, `X-Auth-Token`,
  `Api-Key`, and `Apikey` headers are always replaced with `[REDACTED]`.
- The whole block is passed through `DataMasker`, so bearer tokens, emails, and JSON secret keys
  are masked as well.

Verbose logging is a development tool. Keep `.summary` or `.off` in production builds because
bodies can contain customer data. On a physical device, OSLog privacy settings may require
private-data logging to display dynamic strings in Console.app; the simulator and Xcode's debug
console show them directly.

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
- In the default `.summary` mode, request and response payloads, headers, URL paths, and query
  strings are never logged.
- `.verbose` mode is explicitly opt-in and logs bodies and headers for local debugging only. It
  replaces credential headers with `[REDACTED]` and passes the entire block through `DataMasker`.
- Use `.summary` or `.off` for release builds.
- The session inspector is disabled by default, keeps history in memory only, and redacts
  credential headers unless `sensitiveDataPolicy` is explicitly `.include`.
- A `.include` inspector exposes live bearer tokens in the UI and in copied cURL commands. Use it
  only with local, non-production credentials.
- Redacted cURL commands are documentation, not replayable requests: the `[REDACTED]` token must be
  replaced before execution.
- The default cache policy avoids reusing banking responses from the local HTTP cache.
- The ephemeral `URLSession` avoids persistent disk caches and cookie storage unless the host
  application configures otherwise.
- Authentication headers and tokens should be read from `SecureStorageProtocol`, never hardcoded.
- Always use HTTPS; HTTP connections are blocked by App Transport Security in production builds.

## Threading
- `URLSessionNetworkClient` and `NetworkConfiguration` are `Sendable`.
- Requests are executed with `async/await` and may be issued concurrently.
- `NetworkInspectorProtocol` is thread-safe; recording and `clear()` may be called from any task,
  and `updates()` delivers snapshots to any number of observers.
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
