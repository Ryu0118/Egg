import EggKit
import Foundation

/// Handler for `egg_template_list` tool.
/// Lists all available egg templates.
struct ListHandler: ToolHandler {
    static let toolName = "egg_template_list"

    func execute(with context: ToolContext) async throws -> String {
        let location = context.arguments.optionalString("location")
        let searchPaths = context.arguments.optionalStringArray("template_search_paths")?.map { URL(filePath: $0) } ?? []
        let projectDir = context.arguments.optionalString("project_directory").map { URL(filePath: $0) }

        let service = MCPService(
            workingDirectory: nil,
            projectDirectory: projectDir,
            additionalSearchPaths: searchPaths,
        )

        let result = try await service.listTemplates(location: location)

        return try JSONEncoderHelper.encode(result)
    }
}
