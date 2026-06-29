import ArgumentParser
import EggKit
import FileManagerProtocol
import Foundation
import Noora

package extension EggCommand.TemplateCommand {
    struct MoveCommand: AsyncParsableCommand, HasProjectDirectory, HasTemplateSearchPaths {
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

        @Argument(help: "The name of the template to move (optional for interactive mode).")
        package var templateName: String?

        @Option(name: .long, help: "Target location (project or global).")
        package var to: TemplateLocationType.Kind?

        @Flag(name: .long, help: "Overwrite if target template already exists.")
        package var force: Bool = false

        @Option(name: .long, help: "Directory containing the template to move (defaults to current directory).", completion: .directory)
        package var projectDirectory: String?

        @Option(name: .long, parsing: .upToNextOption, help: "Additional directories to search for templates.", completion: .directory)
        package var templateSearchPaths: [String] = []

        package static let fileManager: any FileManagerProtocol = FileManager.default

        package init() {}

        package mutating func run() async throws {
            let mode = try await validate()
            do {
                try await MoveRunner(
                    mode: mode,
                    force: force,
                    projectDirectory: resolveProjectDirectory(),
                    workingDirectory: URL(filePath: Self.fileManager.currentDirectoryPath),
                    homeDirectory: resolveHomeDirectory(),
                    additionalSearchPaths: resolveTemplateSearchPaths(),
                    fileManager: Self.fileManager,
                ).run()
            } catch {
                Noora().error("\(error.localizedDescription)")
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
                    homeDirectory: resolveHomeDirectory(),
                    additionalSearchPaths: resolveTemplateSearchPaths(),
                    fileManager: Self.fileManager,
                ).validate()
            } catch {
                throw ValidationError(error.localizedDescription)
            }
        }
    }
}
