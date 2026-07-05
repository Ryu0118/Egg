import EggKit
import Foundation

struct HatchTransactionsHandler: ToolHandler {
    static let toolName = "egg_hatch_transactions"

    func execute(with context: ToolContext) async throws -> String {
        let workingDirectory = context.arguments.optionalString("working_directory").map { URL(filePath: $0) }

        let service = MCPService(workingDirectory: workingDirectory)
        let result = service.listHatchTransactions(workingDirectory: workingDirectory)

        return try JSONEncoderHelper.encode(result)
    }
}
