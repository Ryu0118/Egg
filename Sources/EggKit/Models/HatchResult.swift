import Foundation

/// Result of hatching a template for MCP mode.
public struct HatchResult: Codable, Sendable {
    /// Name of the template that was hatched
    public let templateName: String

    /// Directory where the template was hatched
    public let outputDirectory: String

    /// Whether the hatch was successful
    public let success: Bool

    /// Optional message with additional details
    public let message: String?

    /// Files that were created
    public let createdFiles: [String]?

    public init(
        templateName: String,
        outputDirectory: String,
        success: Bool,
        message: String? = nil,
        createdFiles: [String]? = nil
    ) {
        self.templateName = templateName
        self.outputDirectory = outputDirectory
        self.success = success
        self.message = message
        self.createdFiles = createdFiles
    }
}
