import EggKit
import Foundation

struct HatchRollbackHandler: ToolHandler {
    static let toolName = "egg_hatch_rollback"

    func execute(with context: ToolContext) async throws -> String {
        let rollbackId = try context.arguments.requireString("rollback_id")
        let force = context.arguments.bool("force", default: false)
        let workingDirectory = context.arguments.optionalString("working_directory").map { URL(filePath: $0) }

        let service = MCPService(workingDirectory: workingDirectory)
        let result = try await service.rollbackHatchTransaction(
            rollbackId: rollbackId,
            workingDirectory: workingDirectory,
            force: force,
        )

        return try JSONEncoderHelper.encode(result)
    }
}
