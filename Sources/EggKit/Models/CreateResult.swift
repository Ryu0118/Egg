import Foundation

/// Result of creating a template for MCP mode.
public struct CreateResult: Codable, Sendable {
    /// Name of the created template
    public let name: String

    /// Description of the created template
    public let description: String

    /// Location type: "global" or "project"
    public let location: String

    /// Absolute path to the created template directory
    public let path: String

    public init(
        name: String,
        description: String,
        location: String,
        path: String,
    ) {
        self.name = name
        self.description = description
        self.location = location
        self.path = path
    }
}
