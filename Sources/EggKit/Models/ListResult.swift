import Foundation

/// Result of listing templates for MCP mode.
public struct ListResult: Codable, Sendable {
    /// All templates found
    public let templates: [TemplateInfo]

    /// Total count of templates
    public var total: Int {
        templates.count
    }

    public init(templates: [TemplateInfo]) {
        self.templates = templates
    }

    /// Information about a single template
    public struct TemplateInfo: Codable, Sendable {
        /// Template name from config.yml
        public let name: String

        /// Template description from config.yml
        public let description: String

        /// Template version from config.yml (optional)
        public let version: String?

        /// Location type: "global", "project", or "custom"
        public let location: String

        /// Absolute path to the template directory
        public let path: String

        public init(
            name: String,
            description: String,
            version: String?,
            location: String,
            path: String,
        ) {
            self.name = name
            self.description = description
            self.version = version
            self.location = location
            self.path = path
        }
    }
}
