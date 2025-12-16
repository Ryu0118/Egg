import ArgumentParser
import EggKit
import FileManagerProtocol
import Foundation
import Noora

package extension EggCommand.TemplateCommand {
    struct CreateCommand: AsyncParsableCommand, HasProjectDirectory {
        package static let configuration = CommandConfiguration(
            commandName: "create",
            abstract: "Create a new template with config.yml and template files.",
            discussion: """
            This command supports two modes:

            Interactive Mode:
              When no arguments are provided, you will be prompted to enter:
              - Template name
              - Template description
              - Template location (global or project)

            Direct Mode:
              Provide all required information via command-line arguments.
              Example: egg template create --name MyTemplate --description "My template" --location global
            """
        )

        @Option(name: .long, help: "Directory to create the template in.", completion: .directory)
        package var projectDirectory: String?

        @Option(name: .long, help: "The name of the template to create.")
        package var name: String?

        @Option(name: .long, help: "The description of the template to create.")
        package var description: String?

        @Option(
            name: .long,
            help: "Where to store the template: 'global' or 'project' (current directory).",
            completion: .list(["global", "project"])
        )
        package var location: TemplateLocationType.Kind?

        @Flag(name: .long, help: "Skip the creation of the config.yml file.")
        package var skipConfig: Bool = false

        package static let fileManager: any FileManagerProtocol = FileManager.default

        package init() {}

        package mutating func run() async throws {
            let mode = try await validate()
            do {
                try await CreateRunner(
                    mode: mode,
                    skipConfig: skipConfig,
                    projectDirectory: try await resolveProjectDirectory(),
                    workingDirectory: URL(filePath: Self.fileManager.currentDirectoryPath),
                    homeDirectory: resolveHomeDirectory(),
                    fileManager: Self.fileManager
                ).run()
            } catch {
                Noora().error("\(error.localizedDescription)")
            }
        }

        func validate() async throws -> CreateRunnerMode {
            do {
                let projectDirectory = try await resolveProjectDirectory()
                let workingDirectory = URL(filePath: Self.fileManager.currentDirectoryPath)
                return try await CreateArgumentsValidator(
                    name: name,
                    description: description,
                    location: location,
                    projectDirectory: projectDirectory,
                    workingDirectory: workingDirectory,
                    homeDirectory: resolveHomeDirectory(),
                    fileManager: Self.fileManager
                ).validate()
            } catch {
                throw ValidationError(error.localizedDescription)
            }
        }
    }
}
