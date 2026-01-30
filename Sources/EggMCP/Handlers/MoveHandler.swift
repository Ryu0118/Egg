import EggKit
import Foundation

/// Handler for `egg_template_move` tool.
/// Moves a template between locations (global <-> project).
struct MoveHandler: ToolHandler {
    static let toolName = "egg_template_move"

    func execute(with context: ToolContext) async throws -> String {
        let templateName = try context.arguments.requireString("template_name")
        let targetLocation = try context.arguments.requireString("target_location")
        let searchPaths = context.arguments.optionalStringArray("template_search_paths")?.map { URL(filePath: $0) } ?? []
        let projectDir = context.arguments.optionalString("project_directory").map { URL(filePath: $0) }

        let service = MCPService(
            workingDirectory: nil,
            projectDirectory: projectDir,
            additionalSearchPaths: searchPaths
        )

        let result = try await service.moveTemplate(
            templateName: templateName,
            targetLocation: targetLocation
        )

        return try JSONEncoderHelper.encode(result)
    }
}
