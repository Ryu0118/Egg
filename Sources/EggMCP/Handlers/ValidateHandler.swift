import EggKit
import Foundation

/// Handler for `egg_template_validate` tool.
/// Validates a template's config.yml for errors.
struct ValidateHandler: ToolHandler {
    static let toolName = "egg_template_validate"

    func execute(with context: ToolContext) async throws -> String {
        let templatePath = try context.arguments.requireString("template_path")

        let service = EggService()

        let result = try await service.validateTemplate(templatePath: templatePath)

        return try JSONEncoderHelper.encode(result)
    }
}
