import ArgumentParser
import EggKit
import FileSystem
import Foundation
import Noora
import Path

package extension EggCommand.TemplateCommand {
    struct DuplicateCommand: AsyncParsableCommand, HasProjectDirectory {
        package static let configuration = CommandConfiguration(
            commandName: "duplicate",
            abstract: "Duplicate an existing template.",
            discussion: """
            This command supports two modes:

            Interactive Mode:
              When arguments are not provided, you will be prompted to:
              - Select a template to duplicate
              - Enter the name for the new template
              - Enter the description for the new template

            Direct Mode:
              Provide all required information via command-line arguments.
              Example: egg template duplicate MyTemplate --name NewTemplate --description "Duplicated template"
            """
        )

        @Argument(help: "The name of the template to duplicate (optional for interactive mode).")
        package var templateName: String?

        @Option(name: .long, help: "The name for the duplicated template.")
        package var name: String?

        @Option(name: .long, help: "The description for the duplicated template.")
        package var description: String?

        @Option(name: .long, help: "Directory containing the template to duplicate (defaults to current directory).", completion: .directory)
        package var projectDirectory: String?

        package static let fileSystem = FileSystem()

        package init() {}

        package mutating func run() async throws {
            let mode = try await validate()
            do {
                try await DuplicateRunner(
                    mode: mode,
                    projectDirectory: await resolveProjectDirectory(),
                    workingDirectory: await Self.fileSystem.currentWorkingDirectory(),
                    homeDirectory: FileManager.default.homeDirectoryForCurrentUser.absolutePath,
                    fileSystem: Self.fileSystem
                ).run()
            } catch {
                Noora().error("\(error.localizedDescription)")
            }
        }

        func validate() async throws -> DuplicateRunnerMode {
            do {
                return try await DuplicateArgumentsValidator(
                    templateName: templateName,
                    newName: name,
                    newDescription: description,
                    projectDirectory: await resolveProjectDirectory(),
                    workingDirectory: await Self.fileSystem.currentWorkingDirectory(),
                    homeDirectory: FileManager.default.homeDirectoryForCurrentUser.absolutePath,
                    fileSystem: Self.fileSystem
                ).validate()
            } catch {
                throw ValidationError(error.localizedDescription)
            }
        }
    }
}
