import ArgumentParser
import EggKit
import FileManagerProtocol
import Foundation

extension TemplatePickerStyle: ExpressibleByArgument {}

/// `egg hatch` — the scaffolding entry point.
///
/// Everything is a subcommand so there is no positional/subcommand ambiguity:
/// `direct` is the human/inline flow (and the default when no subcommand is
/// given, so a bare `egg hatch` still drops into interactive mode), while
/// `preview`/`apply`/`rollback`/`discard` form the agent-first transaction flow
/// that emits JSON.
package struct HatchCommand: AsyncParsableCommand {
    package static let configuration = CommandConfiguration(
        commandName: "hatch",
        abstract: "Use a template to generate files with macro substitution.",
        discussion: """
        Agent-first transaction flow (emits JSON):
          egg hatch preview <Template> [--macro value ...]   # propose changes + apply token
          egg hatch apply <token>                            # commit changes, record rollback
          egg hatch rollback <id>                            # undo a prior apply
          egg hatch discard <token>                          # drop a preview

        Human / inline flow:
          egg hatch                         # interactive: prompts for template and macros
          egg hatch direct <Template> ...   # applies inline, no preview/token step
        """,
        subcommands: [
            HatchDirectCommand.self,
            HatchPreviewCommand.self,
            HatchApplyCommand.self,
            HatchRollbackCommand.self,
            HatchDiscardCommand.self,
        ],
        defaultSubcommand: HatchDirectCommand.self,
    )

    package init() {}
}

/// `egg hatch direct` — the inline (non-transaction) flow.
///
/// With a template name it applies directly; with none it prompts interactively.
/// This is the default subcommand, so a bare `egg hatch` resolves here.
package struct HatchDirectCommand: AsyncParsableCommand, HasProjectDirectory, HasTemplateSearchPaths {
    @Argument(help: "The name of the template to use (optional, will prompt if not provided).")
    package var templateName: String?

    /// Use .allUnrecognized to capture only unrecognized options/flags as macros
    /// This allows recognized flags like --no-staging to be parsed correctly
    @Argument(parsing: .allUnrecognized, help: "User-defined macro values format (e.g., --user-defined value).")
    package var macros: [String] = []

    @Flag(name: [.long], help: "Disable staging. When set, changes are applied directly without preview or rollback capability.")
    package var noStaging: Bool = false

    @Flag(name: .long, help: "Override conflicts and overwrite existing files without prompting.")
    package var overrideConflicts: Bool = false

    @Flag(name: .long, help: "Disable sandbox-exec safety guard for lifecycle scripts.")
    package var noSandbox: Bool = false

    @Flag(name: .long, help: "Automatically apply changes without prompting for confirmation.")
    package var applyChanges: Bool = false

    @Option(name: .long, help: "Directory where project templates are located (defaults to current directory).", completion: .directory)
    package var projectDirectory: String?

    @Option(name: .long, help: "Directory to use as staging root (defaults to current directory). Use this when template outputs target a different directory.", completion: .directory)
    package var stagingRoot: String?

    @Option(name: .long, help: "Template picker style: 'list' for interactive selection, 'text' for text input.")
    package var picker: TemplatePickerStyle = .list

    @Option(name: .long, parsing: .upToNextOption, help: "Additional directories to search for templates.", completion: .directory)
    package var templateSearchPaths: [String] = []
    package static let configuration = CommandConfiguration(
        commandName: "direct",
        abstract: "Generate files inline without the preview/apply step (interactive when no template is given).",
    )

    package static let fileManager: any FileManagerProtocol = FileManager.default

    package init() {}

    package mutating func run() async throws {
        let mode = try await validate()

        try await HatchRunner(
            mode: mode,
            workingDirectory: URL(filePath: Self.fileManager.currentDirectoryPath),
            homeDirectory: CLIEnvironment.resolveHomeDirectory(),
            projectDirectory: resolveProjectDirectory(),
            additionalSearchPaths: resolveTemplateSearchPaths(),
            fileManager: Self.fileManager,
            useStaging: !noStaging,
            overrideConflicts: overrideConflicts,
            sandboxDisabled: noSandbox,
            applyChanges: applyChanges,
            stagingRoot: resolveStagingRoot(),
            pickerStyle: picker,
        ).run()
    }

    private func resolveStagingRoot() -> URL? {
        guard let stagingRoot else { return nil }
        let url = URL(filePath: stagingRoot, relativeTo: URL(filePath: Self.fileManager.currentDirectoryPath))
        return url.standardizedFileURL
    }

    private func validate() async throws -> HatchRunnerMode {
        do {
            return try await HatchArgumentsValidator(
                templateName: templateName,
                macros: macros,
                projectDirectory: resolveProjectDirectory(),
                workingDirectory: URL(filePath: Self.fileManager.currentDirectoryPath),
                homeDirectory: CLIEnvironment.resolveHomeDirectory(),
                additionalSearchPaths: resolveTemplateSearchPaths(),
                fileManager: Self.fileManager,
            ).validate()
        } catch {
            throw ValidationError(error.localizedDescription)
        }
    }
}
