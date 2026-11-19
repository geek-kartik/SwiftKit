# Session Module

## Purpose & Scope
Manages the authenticated user session: token lifecycle, expiration tracking, secure logout, and authentication state. The module persists the active session through the Secure Storage module and notifies registered observers of authentication transitions. It exposes a small protocol surface so other SDK modules and client applications depend on the abstraction rather than the concrete manager.

- Establishes, restores, refreshes, and clears sessions.
- Persists the session in the Keychain via `SecureStorageProtocol`.
- Tracks expiration lazily and supports explicit lifecycle validation.
- Renews credentials through an injectable `SessionTokenRefreshHandler`, skipping refresh while offline.
- Clears the session on `logout()` and provides `handleUnauthorized()` for HTTP 401 responses (call it from your app; networking does not call it automatically).
- Notifies observers of authentication transitions, suppressing duplicate states.
- Keeps Keychain and storage details internal.

## Apple Frameworks
- `Foundation`

## Architecture
- `Public/SessionManagerProtocol.swift`: Public session management contract.
- `Models/Session.swift`: Public session model (`accessToken`, `refreshToken`, `expiresAt`, `userID`).
- `Public/SessionState.swift`: Public `.unauthenticated` / `.authenticated(Session)` / `.expired` state enum.
- `Public/SessionEvent.swift`: Public transition events (`authenticated`, `refreshed`, `loggedOut`, `expired`, `unauthorized`).
- `Public/SessionObservationToken.swift`: Opaque token used to remove observers.
- `Public/SessionError.swift`: Domain error enum.
- `Public/SessionTokenRefresh.swift`: Public result of a successful token refresh.
- `Public/SessionTokenRefreshHandler.swift`: Public protocol performing the backend token exchange.
- `Internal/SessionManager.swift`: Thread-safe concrete manager persisting through `SecureStorageProtocol`.

The manager is constructed by `SDKDependencyContainer` and exposed through `SwiftKit.shared.session`.

## Public API
| Member | Type | Description |
|---|---|---|
| `currentSession` | `Session?` | The active session, or `nil` when unauthenticated or expired. |
| `isAuthenticated` | `Bool` | Whether an authenticated, non-expired session is active. |
| `state` | `SessionState` | Current authentication state, including `.expired`. |
| `startSession(_:)` | `throws` | Establishes and persists a new session. |
| `restoreSession()` | `throws -> Session?` | Restores the persisted session, retaining it as `.expired` when expired. |
| `refreshSession(accessToken:refreshToken:expiresAt:)` | `throws` | Refreshes the active session with explicit credentials. |
| `refreshSession()` | `async throws -> Session` | Refreshes through the configured handler, skipping refresh while offline. |
| `logout()` | `throws` | Cancels any in-flight refresh and clears the session. |
| `validateExpiry()` | `Void` | Transitions an expired session to `.expired` and emits `.expired`. |
| `handleUnauthorized()` | `Void` | Clears the session after an HTTP 401 and emits `.unauthorized`. |
| `addObserver(_:)` | `SessionObservationToken` | Registers an observer for future transitions. |
| `removeObserver(_:)` | `Void` | Removes a previously registered observer. |

## Usage
```swift
import SwiftKit

let session = SwiftKit.shared.session

// Establish a session after a successful login.
let newSession = Session(
    accessToken: "jwt_access_token",
    refreshToken: "jwt_refresh_token",
    expiresAt: Date().addingTimeInterval(3600),
    userID: "user-123"
)
try session.startSession(newSession)

// Observe authentication transitions.
let token = session.addObserver { event in
    switch event {
    case .authenticated:
        print("Signed in")
    case .refreshed:
        print("Token refreshed")
    case .loggedOut, .expired, .unauthorized:
        print("Signed out")
    }
}

// Restore a persisted session at launch.
try session.restoreSession()

// Refresh credentials through the configured handler.
let refreshed = try await session.refreshSession()

// Clear the session on logout.
try session.logout()
session.removeObserver(token)
```

## Refresh Handler
Supply a `SessionTokenRefreshHandler` through `SwiftKitConfiguration` so the manager can renew
credentials without depending on a concrete networking type:

```swift
struct AppRefreshHandler: SessionTokenRefreshHandler {
    func refresh(using refreshToken: String) async throws -> SessionTokenRefresh {
        let tokens = try await AuthAPI.refresh(refreshToken)
        return SessionTokenRefresh(
            accessToken: tokens.access,
            refreshToken: tokens.refresh,
            expiresAt: tokens.expiry
        )
    }
}

let configuration = SwiftKitConfiguration(sessionTokenRefreshHandler: AppRefreshHandler())
```

`refreshSession()` returns `SessionError.missingRefreshToken`, `.refreshHandlerUnavailable`,
`.offline`, `.refreshCancelled`, or `.refreshFailed` when the corresponding precondition fails.

## Lifecycle
- `startSession(_:)` validates that the expiration is in the future before persisting.
- `restoreSession()` returns `nil` when nothing is stored and retains an already-expired session as
  `.expired` so it can later be refreshed.
- `refreshSession(...)` requires a stored session and preserves the existing user identifier.
- `refreshSession()` skips the exchange only when connectivity is available and reports `.disconnected`; it requires a refresh token and a configured handler.
- `logout()` cancels any in-flight refresh and is tolerant of an absent stored session.
- `validateExpiry()` and `handleUnauthorized()` are idempotent and safe to call repeatedly.
- Observers are only notified when the resulting authentication state actually changes.

There is no idle-timeout mechanism; expiry is based on `expiresAt` and explicit `validateExpiry()` calls. `handleUnauthorized()` is not called by the networking client automatically.

## Threading
- Session and observer state is protected by `ThreadSafeBox`.
- Observer callbacks are invoked synchronously on the thread that produced the transition, outside the
  state lock, so observers may safely call back into the manager.
- The clock is injectable, allowing deterministic expiry tests without sleeping.
- In-flight refreshes run in a tracked `Task` that is cancelled on logout, unauthorized responses, and
  session replacement.
- `SessionManager` uses compiler-checked `Sendable` conformance.

## Security
- The session is persisted as JSON in the Keychain through the Secure Storage module and inherits its
  accessibility policy.
- Access tokens are never written to logs in cleartext.
- Logout and unauthorized handling remove the persisted credentials; expired credentials are retained
  only so the session can be refreshed.
