import EggKit
import Foundation

/// Handler for `egg_template_duplicate` tool.
/// Duplicates an existing template with a new name.
struct DuplicateHandler: ToolHandler {
    static let toolName = "egg_template_duplicate"

    func execute(with context: ToolContext) async throws -> String {
        let sourceName = try context.arguments.requireString("source_template_name")
        let newName = try context.arguments.requireString("new_name")
        let newDescription = context.arguments.optionalString("new_description")
        let searchPaths = context.arguments.optionalStringArray("template_search_paths")?.map { URL(filePath: $0) } ?? []
        let projectDir = context.arguments.optionalString("project_directory").map { URL(filePath: $0) }

        let service = MCPService(
            workingDirectory: nil,
            projectDirectory: projectDir,
            additionalSearchPaths: searchPaths,
        )

        let result = try await service.duplicateTemplate(
            sourceName: sourceName,
            newName: newName,
            newDescription: newDescription,
        )

        return try JSONEncoderHelper.encode(result)
    }
}
