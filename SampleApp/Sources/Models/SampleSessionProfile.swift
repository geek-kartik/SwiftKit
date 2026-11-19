import Foundation

/// Sample Codable model representing an authenticated user profile to demonstrate
/// `setCodable` and `codable` operations on `SecureStorageProtocol`.
public struct SampleSessionProfile: Codable, Equatable, Sendable {
    public let userId: String
    public let username: String
    public let role: String
    public let issuedAt: Date

    public init(
        userId: String,
        username: String,
        role: String,
        issuedAt: Date = Date()
    ) {
        self.userId = userId
        self.username = username
        self.role = role
        self.issuedAt = issuedAt
    }
}
