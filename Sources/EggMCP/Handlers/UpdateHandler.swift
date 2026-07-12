import EggKit
import Foundation

/// Handler for `egg_template_update` tool.
/// Re-resolves eggs.yml to the latest eligible versions and rewrites
/// eggs-lock.yml.
struct UpdateHandler: ToolHandler {
    static let toolName = "egg_template_update"

    func execute(with context: ToolContext) async throws -> String {
        let scope = context.arguments.optionalString("scope")
        let dryRun = context.arguments.bool("dry_run", default: false)
        let projectDir = context.arguments.optionalString("project_directory").map { URL(filePath: $0) }

        let service = EggService(
            workingDirectory: nil,
            projectDirectory: projectDir,
        )

        let result = try await service.updateTemplates(scope: scope, dryRun: dryRun)

        return try JSONEncoderHelper.encode(result.encoded)
    }
}
