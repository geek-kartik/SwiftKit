import Foundation

/// A lightweight thread-safe synchronization container for managing mutable state safely across concurrent threads.
///
/// - Note: This type is intentionally marked `@unchecked Sendable`. All access to the mutable
///   `value` is serialized through `NSLock`, so the conformance is safe even when `Value` itself
///   is not `Sendable`.
public final class ThreadSafeBox<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()

    /// Initializes the box with an initial value.
    public init(_ value: Value) {
        self.value = value
    }

    /// Reads the current value safely under lock.
    public var current: Value {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    /// Mutates the stored value atomically.
    /// - Parameter mutation: Closure performing the state transformation.
    /// - Returns: The result of the mutation closure.
    @discardableResult
    public func mutate<Result>(_ mutation: (inout Value) throws -> Result) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try mutation(&value)
    }

    /// Overwrites the stored value atomically.
    /// - Parameter newValue: The new value to set.
    public func write(_ newValue: Value) {
        lock.lock()
        defer { lock.unlock() }
        value = newValue
    }
}
