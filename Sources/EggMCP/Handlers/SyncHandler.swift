import EggKit
import Foundation

/// Handler for `egg_template_sync` tool.
/// Installs templates declared in egg.yml, honoring egg-lock.yml.
struct SyncHandler: ToolHandler {
    static let toolName = "egg_template_sync"

    func execute(with context: ToolContext) async throws -> String {
        let scope = context.arguments.optionalString("scope")
        let dryRun = context.arguments.bool("dry_run", default: false)
        let projectDir = context.arguments.optionalString("project_directory").map { URL(filePath: $0) }

        let service = EggService(
            workingDirectory: nil,
            projectDirectory: projectDir,
        )

        let result = try await service.syncTemplates(scope: scope, dryRun: dryRun)

        return try JSONEncoderHelper.encode(result.encoded)
    }
}
