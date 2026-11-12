import Foundation

/// Represents the runtime environment for the SwiftKit SDK.
public enum SDKEnvironment: String, CaseIterable, Sendable {
    /// Development environment for local testing and debugging.
    case development
    /// User Acceptance Testing environment for QA and staging validation.
    case uat
    /// Production environment for live end-user application instances.
    case production

    /// Indicates whether the environment corresponds to production.
    public var isProduction: Bool {
        self == .production
    }

    /// Descriptive title for logging and diagnostic purposes.
    public var displayName: String {
        switch self {
        case .development:
            return "Development"
        case .uat:
            return "UAT"
        case .production:
            return "Production"
        }
    }
}
