import EggKit
import Foundation

/// Handler for `egg_template_install` tool.
/// Installs templates from a Git repository or local path.
struct InstallHandler: ToolHandler {
    static let toolName = "egg_template_install"

    func execute(with context: ToolContext) async throws -> String {
        let source = try context.arguments.requireString("source")
        let location = try context.arguments.requireString("location")
        let include = context.arguments.optionalStringArray("include")
        let exclude = context.arguments.optionalStringArray("exclude")
        let branch = context.arguments.optionalString("branch")
        let tag = context.arguments.optionalString("tag")
        let revision = context.arguments.optionalString("revision")
        let projectDir = context.arguments.optionalString("project_directory").map { URL(filePath: $0) }

        let service = EggService(
            workingDirectory: nil,
            projectDirectory: projectDir,
        )

        let result = try await service.installTemplates(
            source: source,
            location: location,
            branch: branch,
            tag: tag,
            revision: revision,
            include: include,
            exclude: exclude,
        )

        return try JSONEncoderHelper.encode(result.encoded)
    }
}
