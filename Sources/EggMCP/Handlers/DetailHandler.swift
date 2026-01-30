import EggKit
import Foundation

/// Handler for `egg_template_detail` tool.
/// Returns detailed information about a specific template.
struct DetailHandler: ToolHandler {
    static let toolName = "egg_template_detail"

    func execute(with context: ToolContext) async throws -> String {
        let templateName = try context.arguments.requireString("template_name")
        let searchPaths = context.arguments.optionalStringArray("template_search_paths")?.map { URL(filePath: $0) } ?? []
        let projectDir = context.arguments.optionalString("project_directory").map { URL(filePath: $0) }

        let service = MCPService(
            workingDirectory: nil,
            projectDirectory: projectDir,
            additionalSearchPaths: searchPaths
        )

        let result = try await service.templateDetail(templateName: templateName)

        return try JSONEncoderHelper.encode(result)
    }
}
