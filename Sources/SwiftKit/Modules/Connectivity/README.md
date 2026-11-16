# Connectivity Module

## Purpose & Scope
Monitors system network-path connectivity using Apple's `Network` framework (`NWPathMonitor`) and notifies registered observers when the path transitions between unknown, connected, and disconnected. The module exposes a small protocol surface so other SDK modules and client applications depend on the abstraction rather than the concrete monitor.

- Reports the latest known path status.
- Starts in an explicit `unknown` state so the app does not treat startup as offline.
- Emits the current status snapshot immediately when an observer is registered.
- Supports idempotent start and stop lifecycle operations.
- Delivers observer callbacks only when the status actually changes.
- Keeps `NWPathMonitor` implementation details internal.

> **Note:** This module reports the operating system's network-path status. A `.connected` status means the system has a satisfied path; it does **not** guarantee internet reachability or backend availability.

## Apple Frameworks
- `Network` (`NWPathMonitor`, `NWPath.Status`)
- `Foundation`

## Architecture
- `Public/ConnectivityMonitorProtocol.swift`: Public monitoring contract.
- `Public/ConnectivityStatus.swift`: Public `.unknown` / `.connected` / `.disconnected` status enum.
- `Public/ConnectivityObservationToken.swift`: Opaque token used to remove observers.
- `Internal/NetworkConnectivityMonitor.swift`: Thread-safe concrete monitor managing lifecycle, state, and observer delivery.
- `Internal/NetworkPathMonitorEngine.swift`: Internal abstraction over `NWPathMonitor` plus the concrete `NWPathMonitor`-backed engine and factory.

The monitor is constructed by `SDKDependencyContainer` and exposed through `SwiftKit.shared.connectivity`. Inject the protocol into modules that need connectivity awareness.

## Usage Example
```swift
import SwiftKit

let connectivity = SwiftKit.shared.connectivity

let token = connectivity.addObserver { status in
    switch status {
    case .unknown:
        print("Connectivity not determined yet")
    case .connected:
        print("Network path available")
    case .disconnected:
        print("Network path unavailable")
    }
}

connectivity.start()

// Later, when updates are no longer needed:
connectivity.removeObserver(token)
connectivity.stop()
```

Check the current state at any time:
```swift
let isConnected = connectivity.currentStatus.isConnected
let isMonitoring = connectivity.isMonitoring
```

Consuming modules should accept `ConnectivityMonitorProtocol` rather than constructing `NetworkConnectivityMonitor` directly:
```swift
internal final class NetworkingClient {
    private let connectivity: ConnectivityMonitorProtocol

    internal init(connectivity: ConnectivityMonitorProtocol) {
        self.connectivity = connectivity
    }
}
```

## Lifecycle
- `start()` is idempotent: repeated calls while monitoring is active do not create additional monitors.
- `stop()` is idempotent: repeated calls are safe.
- Calling `start()` after `stop()` begins a new monitoring session with a fresh underlying monitor.
- The monitor cancels its engine on deallocation.
- Updates produced by a previous session are discarded after `stop()`.

## Threading
- Path updates are processed on a dedicated serial queue (`com.swiftkit.connectivity.monitor`, `.utility` QoS).
- Status-change callbacks are invoked on that same serial queue, not on the main thread. Observers performing UI work must dispatch to the main queue themselves.
- The initial status snapshot is delivered synchronously on the registering thread when `addObserver` is called.
- Shared status, lifecycle state, and observer collections are protected by `ThreadSafeBox`.
- `NetworkConnectivityMonitor` uses compiler-checked `Sendable` conformance; only the internal `NWPathMonitorEngine` is `@unchecked Sendable` because Apple's `NWPathMonitor` is not `Sendable`.
- Observer callbacks are invoked outside the state lock, so observers may safely register, remove, start, or stop from within a callback.

## Status Semantics
- `.unknown` is the initial status before the first path update arrives. Treat it as a pending state, not as offline.
- Registering an observer immediately emits the current status, including `.unknown` when monitoring has not produced a result yet.
- Stopping monitoring retains the last observed status.
- Notifications are emitted only when the status differs from the previously observed value.
