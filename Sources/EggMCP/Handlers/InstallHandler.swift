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
        let ref = context.arguments.optionalString("ref")
        let projectDir = context.arguments.optionalString("project_directory").map { URL(filePath: $0) }

        let service = EggService(
            workingDirectory: nil,
            projectDirectory: projectDir,
        )

        let result = try await service.installTemplates(
            source: source,
            location: location,
            ref: ref,
            include: include,
            exclude: exclude,
        )

        // Convert to JSON-encodable response
        let response = InstallResponse(
            installed: result.installed,
            skipped: result.skipped.map { InstallResponse.SkippedItem(name: $0.name, reason: $0.reason.description) },
            failed: result.failed.map { InstallResponse.FailedItem(name: $0.name, error: $0.error.localizedDescription) },
        )

        return try JSONEncoderHelper.encode(response)
    }
}

// MARK: - Response Types

private struct InstallResponse: Codable {
    let installed: [String]
    let skipped: [SkippedItem]
    let failed: [FailedItem]

    struct SkippedItem: Codable {
        let name: String
        let reason: String
    }

    struct FailedItem: Codable {
        let name: String
        let error: String
    }
}

extension SkipReason {
    var description: String {
        switch self {
        case .alreadyExists:
            "already_exists"
        case .excludedByFilter:
            "excluded_by_filter"
        }
    }
}
