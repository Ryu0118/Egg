import Foundation

/// Result of validating a template for MCP mode.
public struct ValidateResult: Codable, Sendable {
    /// Name of the validated template
    public let templateName: String

    /// Absolute path to the template directory
    public let templatePath: String

    /// Whether the template is valid
    public let isValid: Bool

    /// Validation errors (if any)
    public let errors: [String]?

    public init(
        templateName: String,
        templatePath: String,
        isValid: Bool,
        errors: [String]? = nil
    ) {
        self.templateName = templateName
        self.templatePath = templatePath
        self.isValid = isValid
        self.errors = errors
    }
}
