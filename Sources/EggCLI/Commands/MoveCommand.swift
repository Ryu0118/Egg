import ArgumentParser
import EggKit
import FileManagerProtocol
import Foundation

package extension EggCommand.TemplateCommand {
    struct MoveCommand: AsyncParsableCommand, HasProjectDirectory, HasTemplateSearchPaths {
        @Argument(help: "The name of the template to move (optional for interactive mode).")
        package var templateName: String?

        @Flag(name: .long, help: "Overwrite if target template already exists.")
        package var force: Bool = false

        @Flag(name: .long, help: "Emit machine-readable JSON on stdout instead of the human-readable output. Requires a template name and --to, and overwrites an existing target.")
        package var json = false

        @Option(name: .long, help: "Target location (project or global).")
        package var to: TemplateLocationType.Kind?

        @Option(name: .long, help: "Directory containing the template to move (defaults to current directory).", completion: .directory)
        package var projectDirectory: String?

        @Option(name: .long, parsing: .upToNextOption, help: "Additional directories to search for templates.", completion: .directory)
        package var templateSearchPaths: [String] = []

        package static let configuration = CommandConfiguration(
            commandName: "move",
            abstract: "Move a template between project and global locations.",
            discussion: """
            This command supports three modes:

            Interactive Mode:
              When no arguments are provided, you will be prompted to:
              - Select a template to move
              - Select the target location (project or global)

            Select Target Mode:
              When only template name is provided, you will be prompted to:
              - Select the target location (project or global)
              Example: egg template move MyTemplate

            Direct Mode:
              Provide all required information via command-line arguments.
              Example: egg template move MyTemplate --to global
              Use --force to overwrite if the target already exists.
            """,
        )

        package static let fileManager: any FileManagerProtocol = FileManager.default

        package init() {}

        package mutating func run() async throws {
            if json {
                guard let templateName, let to else {
                    throw ValidationError("--json requires a template name and --to (interactive prompts need a TTY).")
                }
                let result = try await EggService(
                    fileManager: Self.fileManager,
                    projectDirectory: resolveProjectDirectory(),
                    homeDirectory: CLIEnvironment.resolveHomeDirectory(),
                    additionalSearchPaths: resolveTemplateSearchPaths(),
                ).moveTemplate(templateName: templateName, targetLocation: to.rawValue)
                try CLIOutput.printJSON(result)
                return
            }
            let mode = try await validate()
            do {
                try await MoveRunner(
                    mode: mode,
                    force: force,
                    projectDirectory: resolveProjectDirectory(),
                    workingDirectory: URL(filePath: Self.fileManager.currentDirectoryPath),
                    homeDirectory: CLIEnvironment.resolveHomeDirectory(),
                    additionalSearchPaths: resolveTemplateSearchPaths(),
                    fileManager: Self.fileManager,
                ).run()
            } catch {
                CLIOutput.printError(error.localizedDescription)
            }
        }

        func validate() async throws -> MoveRunnerMode {
            do {
                let projectDirectory = try await resolveProjectDirectory()
                let workingDirectory = URL(filePath: Self.fileManager.currentDirectoryPath)
                return try await MoveArgumentsValidator(
                    templateName: templateName,
                    to: to,
                    force: force,
                    projectDirectory: projectDirectory,
                    workingDirectory: workingDirectory,
                    homeDirectory: CLIEnvironment.resolveHomeDirectory(),
                    additionalSearchPaths: resolveTemplateSearchPaths(),
                    fileManager: Self.fileManager,
                ).validate()
            } catch {
                throw ValidationError(error.localizedDescription)
            }
        }
    }
}
