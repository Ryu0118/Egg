import EggKit
import Foundation

struct HatchPreviewHandler: ToolHandler {
    static let toolName = "egg_hatch_preview"

    func execute(with context: ToolContext) async throws -> String {
        let templateName = try context.arguments.requireString("template_name")
        let macros = context.arguments.optionalMacros("macros") ?? [:]
        let searchPaths = context.arguments.optionalStringArray("template_search_paths")?.map { URL(filePath: $0) } ?? []
        let projectDir = context.arguments.optionalString("project_directory").map { URL(filePath: $0) }
        let outputDir = context.arguments.optionalString("output_directory").map { URL(filePath: $0) }

        let service = MCPService(
            workingDirectory: outputDir,
            projectDirectory: projectDir,
            additionalSearchPaths: searchPaths,
        )

        let result = try await service.previewHatchTemplate(
            templateName: templateName,
            macros: macros,
            outputDirectory: outputDir,
        )

        return try JSONEncoderHelper.encode(result)
    }
}
