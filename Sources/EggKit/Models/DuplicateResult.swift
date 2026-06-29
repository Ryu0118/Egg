import Foundation

/// Result of duplicating a template for MCP mode.
public struct DuplicateResult: Codable, Sendable {
    /// Name of the source template
    public let sourceName: String

    /// Name of the new template
    public let newName: String

    /// Description of the new template
    public let newDescription: String

    /// Location type: "global", "project", or "custom"
    public let location: String

    /// Absolute path to the new template directory
    public let path: String

    public init(
        sourceName: String,
        newName: String,
        newDescription: String,
        location: String,
        path: String,
    ) {
        self.sourceName = sourceName
        self.newName = newName
        self.newDescription = newDescription
        self.location = location
        self.path = path
    }
}
