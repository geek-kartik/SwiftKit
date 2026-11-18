import Foundation

/// HTTP methods supported by the SwiftKit networking layer.
///
/// The raw value is the canonical uppercase token transmitted on the wire.
public enum HTTPMethod: String, CaseIterable, Sendable {
    /// Retrieves a representation of a resource.
    case get = "GET"

    /// Creates a new resource using the supplied body.
    case post = "POST"

    /// Replaces a resource with the supplied body.
    case put = "PUT"

    /// Applies a partial update to a resource using the supplied body.
    case patch = "PATCH"

    /// Deletes a resource.
    case delete = "DELETE"

    /// Whether the method may carry a request body.
    ///
    /// `GET` requests must not include a body; the networking layer rejects them.
    internal var allowsRequestBody: Bool {
        self != .get
    }
}
