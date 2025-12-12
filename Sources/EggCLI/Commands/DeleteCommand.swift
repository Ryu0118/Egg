import ArgumentParser
import EggKit
import FileManagerProtocol
import Foundation
import Noora

package extension EggCommand.TemplateCommand {
    struct DeleteCommand: AsyncParsableCommand, HasProjectDirectory {
        package static let configuration = CommandConfiguration(
            commandName: "delete",
            abstract: "Delete a template.",
            discussion: """
            This command supports two modes:

            Interactive Mode:
              When no template name is provided, you will be prompted to:
              - Select a template from the available templates

            Direct Mode:
              Provide the template name as an argument.
              Example: egg template delete MyTemplate
              Use --force to skip confirmation prompt.
            """
        )

        @Argument(help: "The name of the template to delete (optional for interactive mode).")
        package var templateName: String?

        @Option(name: .long, help: "Directory containing the template to delete (defaults to current directory).", completion: .directory)
        package var projectDirectory: String?

        @Option(name: .long, help: "Delete the template without confirmation.")
        package var force: Bool = false

        package static let fileManager: any FileManagerProtocol = FileManager.default

        package init() {}

        package mutating func run() async throws {
            let mode = try await validate()
            do {
                try await DeleteRunner(
                    mode: mode,
                    force: force,
                    projectDirectory: try await resolveProjectDirectory(),
                    workingDirectory: URL(filePath: Self.fileManager.currentDirectoryPath),
                    homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
                    fileManager: Self.fileManager
                ).run()
            } catch {
                Noora().error("\(error.localizedDescription)")
            }
        }

        func validate() async throws -> DeleteRunnerMode {
            do {
                let projectDirectory = try await resolveProjectDirectory()
                let workingDirectory = URL(filePath: Self.fileManager.currentDirectoryPath)
                return try await DeleteArgumentsValidator(
                    templateName: templateName,
                    projectDirectory: projectDirectory,
                    workingDirectory: workingDirectory,
                    homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
                    fileManager: Self.fileManager
                ).validate()
            } catch {
                throw ValidationError(error.localizedDescription)
            }
        }
    }
}
