import EggKit
import Foundation

struct HatchApplyHandler: ToolHandler {
    static let toolName = "egg_hatch_apply"

    func execute(with context: ToolContext) async throws -> String {
        let applyToken = try context.arguments.requireString("apply_token")
        let force = context.arguments.bool("force", default: false)
        let workingDirectory = context.arguments.optionalString("working_directory").map { URL(filePath: $0) }

        let service = EggService(workingDirectory: workingDirectory)
        let result = try await service.applyHatchTransaction(
            applyToken: applyToken,
            workingDirectory: workingDirectory,
            force: force,
        )

        return try JSONEncoderHelper.encode(result)
    }
}
