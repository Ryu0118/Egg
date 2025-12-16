import ArgumentParser
import EggKit
import FileManagerProtocol
import Foundation

extension TemplatePickerStyle: ExpressibleByArgument {}

package struct HatchCommand: AsyncParsableCommand, HasProjectDirectory {
    package static let configuration = CommandConfiguration(
        commandName: "hatch",
        abstract: "Use a template to generate files with macro substitution.",
        discussion: """
        This command supports two modes:

        Interactive Mode:
          When no arguments are provided, the command runs in interactive mode.
          You will be prompted to:
          1. Enter the template name
          2. Answer questions for each macro defined in the template's config

        Direct Mode:
          Provide the template name and macro values via command-line arguments.
          Example: egg hatch MyTemplate --name value --enabled true
        """
    )

    @Argument(help: "The name of the template to use (optional, will prompt if not provided).")
    package var templateName: String?

    @Option(name: .long, help: "Directory where project templates are located (defaults to current directory).", completion: .directory)
    package var projectDirectory: String?

    @Argument(parsing: .captureForPassthrough, help: "User-defined macro values format (e.g., --user-defined value).")
    package var macros: [String] = []

    @Flag(name: [.long], help: "Disable staging. When set, changes are applied directly without preview or rollback capability.")
    package var noStaging: Bool = false

    @Flag(name: .long, help: "Override conflicts and overwrite existing files without prompting.")
    package var overrideConflicts: Bool = false

    @Flag(name: .long, help: "Disable sandbox-exec safety guard for lifecycle scripts.")
    package var noSandbox: Bool = false

    @Flag(name: .long, help: "Automatically apply changes without prompting for confirmation.")
    package var applyChanges: Bool = false

    @Option(name: .long, help: "Directory to use as staging root (defaults to current directory). Use this when template outputs target a different directory.", completion: .directory)
    package var stagingRoot: String?

    @Option(name: .long, help: "Template picker style: 'list' for interactive selection, 'text' for text input.")
    package var picker: TemplatePickerStyle = .list

    package static let fileManager: any FileManagerProtocol = FileManager.default

    package init() {}

    package mutating func run() async throws {
        let mode = try await validate()

        try await HatchRunner(
            mode: mode,
            workingDirectory: URL(filePath: Self.fileManager.currentDirectoryPath),
            homeDirectory: resolveHomeDirectory(),
            projectDirectory: try await resolveProjectDirectory(),
            fileManager: Self.fileManager,
            useStaging: !noStaging,
            overrideConflicts: overrideConflicts,
            sandboxDisabled: noSandbox,
            applyChanges: applyChanges,
            stagingRoot: resolveStagingRoot(),
            pickerStyle: picker
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
                projectDirectory: try await resolveProjectDirectory(),
                workingDirectory: URL(filePath: Self.fileManager.currentDirectoryPath),
                homeDirectory: resolveHomeDirectory(),
                fileManager: Self.fileManager
            ).validate()
        } catch {
            throw ValidationError(error.localizedDescription)
        }
    }
}
