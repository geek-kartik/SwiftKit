import Foundation

/// Errors produced during SDK lifecycle management and configuration validation.
public enum SDKError: Error, LocalizedError, Equatable, Sendable {
    /// SwiftKit has already been initialized and re-initialization was attempted.
    case alreadyInitialized
    /// SwiftKit has not been initialized. Call `SwiftKit.initialize(configuration:)` first.
    case notInitialized
    /// The configuration supplied during initialization failed validation rules.
    case invalidConfiguration(reason: String)
    /// A required internal service or dependency was missing or could not be instantiated.
    case dependencyMissing(dependencyName: String)

    public var errorDescription: String? {
        switch self {
        case .alreadyInitialized:
            return "SwiftKit has already been initialized. Re-initialization is disallowed."
        case .notInitialized:
            return "SwiftKit has not been initialized. Please invoke SwiftKit.initialize(configuration:) before accessing shared utilities."
        case .invalidConfiguration(let reason):
            return "Invalid SwiftKit configuration: \(reason)"
        case .dependencyMissing(let dependencyName):
            return "A critical SwiftKit dependency '\(dependencyName)' is missing or failed initialization."
        }
    }
}
