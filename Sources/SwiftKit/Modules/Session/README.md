# Session Module

## Purpose & Scope
Manages the authenticated user session: token lifecycle, expiration tracking, secure logout, and authentication state. The module persists the active session through the Secure Storage module and notifies registered observers of authentication transitions. It exposes a small protocol surface so other SDK modules and client applications depend on the abstraction rather than the concrete manager.

- Establishes, restores, refreshes, and clears sessions.
- Persists the session in the Keychain via `SecureStorageProtocol`.
- Tracks expiration lazily and supports explicit lifecycle validation.
- Clears the session on logout, expiry, and HTTP 401 unauthorized responses.
- Notifies observers of authentication transitions.
- Keeps Keychain and storage details internal.

## Apple Frameworks
- `Foundation`

## Module Owner
Developer 3

## Architecture
- `Public/SessionManagerProtocol.swift`: Public session management contract.
- `Public/Session.swift`: Public session model (`accessToken`, `refreshToken`, `expiresAt`, `userID`).
- `Public/SessionState.swift`: Public `.unauthenticated` / `.authenticated(Session)` state enum.
- `Public/SessionEvent.swift`: Public transition events (`authenticated`, `refreshed`, `loggedOut`, `expired`, `unauthorized`).
- `Public/SessionObservationToken.swift`: Opaque token used to remove observers.
- `Public/SessionError.swift`: Domain error enum.
- `Internal/SessionManager.swift`: Thread-safe concrete manager persisting through `SecureStorageProtocol`.

The manager is constructed by `SDKDependencyContainer` and exposed through `SwiftKit.shared.session`.

## Public API
| Member | Type | Description |
|---|---|---|
| `currentSession` | `Session?` | The active session, or `nil` when unauthenticated or expired. |
| `isAuthenticated` | `Bool` | Whether an authenticated, non-expired session is active. |
| `state` | `SessionState` | Current authentication state. |
| `startSession(_:)` | `throws` | Establishes and persists a new session. |
| `restoreSession()` | `throws -> Session?` | Restores the persisted session, clearing it when expired. |
| `refreshSession(accessToken:refreshToken:expiresAt:)` | `throws` | Refreshes the active session, preserving the user identifier. |
| `logout()` | `throws` | Clears the session from memory and secure storage. |
| `validateExpiry()` | `Void` | Discards an expired session and emits `.expired`. |
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

// Clear the session on logout.
try session.logout()
session.removeObserver(token)
```

## Lifecycle
- `startSession(_:)` validates that the expiration is in the future before persisting.
- `restoreSession()` returns `nil` when nothing is stored and clears an already-expired session.
- `refreshSession(...)` requires an active session and preserves the existing user identifier.
- `logout()` is tolerant of an absent stored session.
- `validateExpiry()` and `handleUnauthorized()` are idempotent and safe to call repeatedly.

## Threading
- Session and observer state is protected by `ThreadSafeBox`.
- Observer callbacks are invoked synchronously on the thread that produced the transition, outside the
  state lock, so observers may safely call back into the manager.
- The clock is injectable, allowing deterministic expiry tests without sleeping.
- `SessionManager` uses compiler-checked `Sendable` conformance.

## Security
- The session is persisted as JSON in the Keychain through the Secure Storage module and inherits its
  accessibility policy.
- Access tokens are never written to logs in cleartext.
- Logout, expiry, and unauthorized handling all remove the persisted credentials.
