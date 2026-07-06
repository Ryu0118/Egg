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
        let include = context.arguments.optionalStringArray("include") ?? []
        let exclude = context.arguments.optionalStringArray("exclude") ?? []
        let includeDiff = context.arguments.bool("include_diff", default: false)
        let disableSandbox = context.arguments.bool("disable_sandbox", default: false)
        let userConfirmedNoSandbox = context.arguments.bool("user_confirmed_no_sandbox", default: false)
        let allowedWritePaths = context.arguments.optionalStringArray("allowed_write_paths") ?? []
        let allowLargeStaging = context.arguments.bool("allow_large_staging", default: false)
        let allowNonGitStaging = context.arguments.bool("allow_non_git_staging", default: false)

        let service = EggService(
            workingDirectory: outputDir,
            projectDirectory: projectDir,
            additionalSearchPaths: searchPaths,
        )

        let result = try await service.previewHatchTemplate(
            templateName: templateName,
            macros: macros,
            outputDirectory: outputDir,
            include: include,
            exclude: exclude,
            includeDiff: includeDiff,
            disableSandbox: disableSandbox,
            userConfirmedNoSandbox: userConfirmedNoSandbox,
            allowedWritePaths: allowedWritePaths,
            allowLargeStaging: allowLargeStaging,
            allowNonGitStaging: allowNonGitStaging,
        )

        return try JSONEncoderHelper.encode(result)
    }
}
