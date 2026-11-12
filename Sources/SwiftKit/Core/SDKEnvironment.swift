import Foundation

/// Represents the runtime environment for the SwiftKit SDK.
/// SwiftKit is strictly built for internal company projects and operates exclusively in development mode.
public enum SDKEnvironment: String, CaseIterable, Sendable {
    /// Development environment for internal company testing, debugging, and experimentation.
    case development

    /// Descriptive title for logging and diagnostic purposes.
    public var displayName: String {
        switch self {
        case .development:
            return "Development"
        }
    }
}
