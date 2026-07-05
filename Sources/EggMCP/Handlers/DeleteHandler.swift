import EggKit
import Foundation

/// Handler for `egg_template_delete` tool.
/// Deletes an existing template.
struct DeleteHandler: ToolHandler {
    static let toolName = "egg_template_delete"

    func execute(with context: ToolContext) async throws -> String {
        let templateName = try context.arguments.requireString("template_name")
        let searchPaths = context.arguments.optionalStringArray("template_search_paths")?.map { URL(filePath: $0) } ?? []
        let projectDir = context.arguments.optionalString("project_directory").map { URL(filePath: $0) }

        let service = EggService(
            workingDirectory: nil,
            projectDirectory: projectDir,
            additionalSearchPaths: searchPaths,
        )

        let result = try await service.deleteTemplate(templateName: templateName)

        return try JSONEncoderHelper.encode(result)
    }
}
