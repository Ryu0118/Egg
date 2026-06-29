import EggKit
import Foundation

/// Handler for `egg_hatch` tool.
/// Hatches a template with the provided macro values.
struct HatchHandler: ToolHandler {
    static let toolName = "egg_hatch"

    func execute(with context: ToolContext) async throws -> String {
        let templateName = try context.arguments.requireString("template_name")
        let macros = context.arguments.optionalMacros("macros") ?? [:]
        let searchPaths = context.arguments.optionalStringArray("template_search_paths")?.map { URL(filePath: $0) } ?? []
        let projectDir = context.arguments.optionalString("project_directory").map { URL(filePath: $0) }
        let outputDir = context.arguments.optionalString("output_directory").map { URL(filePath: $0) }
        let stagingRoot = context.arguments.optionalString("staging_root").map { URL(filePath: $0) }
        let useStaging = context.arguments.bool("use_staging", default: true)
        let applyChanges = context.arguments.bool("apply_changes", default: true)

        let service = MCPService(
            workingDirectory: outputDir,
            projectDirectory: projectDir,
            additionalSearchPaths: searchPaths,
        )

        let result = try await service.hatchTemplate(
            templateName: templateName,
            macros: macros,
            outputDirectory: outputDir,
            useStaging: useStaging,
            applyChanges: applyChanges,
            stagingRoot: stagingRoot,
        )

        return try JSONEncoderHelper.encode(result)
    }
}
