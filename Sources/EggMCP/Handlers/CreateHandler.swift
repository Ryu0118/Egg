import EggKit
import Foundation

/// Handler for `egg_template_create` tool.
/// Creates a new empty template with the specified name and description.
struct CreateHandler: ToolHandler {
    static let toolName = "egg_template_create"

    func execute(with context: ToolContext) async throws -> String {
        let name = try context.arguments.requireString("name")
        let description = try context.arguments.requireString("description")
        let location = try context.arguments.requireString("location")
        let projectDir = context.arguments.optionalString("project_directory").map { URL(filePath: $0) }

        let service = MCPService(
            workingDirectory: nil,
            projectDirectory: projectDir
        )

        let result = try await service.createTemplate(
            name: name,
            description: description,
            location: location
        )

        return try JSONEncoderHelper.encode(result)
    }
}
