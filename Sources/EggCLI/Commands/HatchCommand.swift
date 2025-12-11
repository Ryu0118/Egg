import ArgumentParser
import EggKit
import FileSystem
import Foundation

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
          Example: egg hatch MyTemplate --NAME value --ENABLED true
        """
    )

    @Argument(help: "The name of the template to use (optional, will prompt if not provided).")
    package var templateName: String?

    @Option(name: .long, help: "Directory where project templates are located (defaults to current directory).", completion: .directory)
    package var projectDirectory: String?

    @Argument(parsing: .captureForPassthrough, help: "User-defined macro values format (e.g., --user-defined value).")
    package var macros: [String] = []

    @Flag(name: .long, help: "Disable sandbox mode. When set, changes are applied directly without preview or rollback capability.")
    package var noSandbox: Bool = false

    @Flag(name: .long, help: "Force overwrite existing files without prompting.")
    package var force: Bool = false

    package static let fileSystem = FileSystem()

    package init() {}

    package mutating func run() async throws {
        let mode = try await validate()

        try await HatchRunner(
            mode: mode,
            workingDirectory: Self.fileSystem.currentWorkingDirectory(),
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser.absolutePath,
            projectDirectory: resolveProjectDirectory(),
            fileSystem: Self.fileSystem,
            useSandbox: !noSandbox,
            force: force
        ).run()
    }

    private func validate() async throws -> HatchRunnerMode {
        do {
            return try await HatchArgumentsValidator(
                templateName: templateName,
                macros: macros,
                projectDirectory: resolveProjectDirectory(),
                workingDirectory: Self.fileSystem.currentWorkingDirectory(),
                homeDirectory: FileManager.default.homeDirectoryForCurrentUser.absolutePath,
                fileSystem: Self.fileSystem
            ).validate()
        } catch {
            throw ValidationError(error.localizedDescription)
        }
    }
}
