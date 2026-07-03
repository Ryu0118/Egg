import EggKit
import Foundation

struct HatchDiscardHandler: ToolHandler {
    static let toolName = "egg_hatch_discard"

    func execute(with context: ToolContext) async throws -> String {
        let applyToken = try context.arguments.requireString("apply_token")
        let workingDirectory = context.arguments.optionalString("working_directory").map { URL(filePath: $0) }

        let service = MCPService(workingDirectory: workingDirectory)
        let result = try await service.discardHatchTransaction(
            applyToken: applyToken,
            workingDirectory: workingDirectory,
        )

        return try JSONEncoderHelper.encode(result)
    }
}
