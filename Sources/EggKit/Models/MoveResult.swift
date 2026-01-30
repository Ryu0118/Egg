import Foundation

/// Result of moving a template for MCP mode.
public struct MoveResult: Codable, Sendable {
    /// Name of the moved template
    public let name: String

    /// Source location type: "global" or "project"
    public let sourceLocation: String

    /// Target location type: "global" or "project"
    public let targetLocation: String

    /// Absolute path to the new location
    public let newPath: String

    public init(
        name: String,
        sourceLocation: String,
        targetLocation: String,
        newPath: String
    ) {
        self.name = name
        self.sourceLocation = sourceLocation
        self.targetLocation = targetLocation
        self.newPath = newPath
    }
}
