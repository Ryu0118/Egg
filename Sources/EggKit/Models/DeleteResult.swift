import Foundation

/// Result of deleting a template for MCP mode.
public struct DeleteResult: Codable, Sendable {
    /// Name of the deleted template
    public let name: String

    /// Location type: "global" or "project"
    public let location: String

    /// Path where the template was located before deletion
    public let path: String

    public init(
        name: String,
        location: String,
        path: String,
    ) {
        self.name = name
        self.location = location
        self.path = path
    }
}
