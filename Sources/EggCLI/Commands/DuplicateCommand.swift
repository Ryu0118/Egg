import ArgumentParser
import EggKit
import FileManagerProtocol
import Foundation

package extension EggCommand.TemplateCommand {
    struct DuplicateCommand: AsyncParsableCommand, HasProjectDirectory, HasTemplateSearchPaths {
        @Argument(help: "The name of the template to duplicate (optional for interactive mode).")
        package var templateName: String?

        @Option(name: .long, help: "The name for the duplicated template.")
        package var name: String?

        @Option(name: .long, help: "The description for the duplicated template.")
        package var description: String?

        @Option(name: .long, help: "Directory containing the template to duplicate (defaults to current directory).", completion: .directory)
        package var projectDirectory: String?

        @Option(name: .long, parsing: .upToNextOption, help: "Additional directories to search for templates.", completion: .directory)
        package var templateSearchPaths: [String] = []
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
            """,
        )

        package static let fileManager: any FileManagerProtocol = FileManager.default

        package init() {}

        package mutating func run() async throws {
            let mode = try await validate()
            do {
                let workingDirectory = URL(filePath: Self.fileManager.currentDirectoryPath)
                let homeDirectory = CLIEnvironment.resolveHomeDirectory()
                try await DuplicateRunner(
                    mode: mode,
                    projectDirectory: resolveProjectDirectory(),
                    workingDirectory: workingDirectory,
                    homeDirectory: homeDirectory,
                    additionalSearchPaths: resolveTemplateSearchPaths(),
                    fileManager: Self.fileManager,
                ).run()
            } catch {
                CLIOutput.printError(error.localizedDescription)
            }
        }

        func validate() async throws -> DuplicateRunnerMode {
            do {
                let workingDirectory = URL(filePath: Self.fileManager.currentDirectoryPath)
                let homeDirectory = CLIEnvironment.resolveHomeDirectory()
                return try await DuplicateArgumentsValidator(
                    templateName: templateName,
                    newName: name,
                    newDescription: description,
                    projectDirectory: resolveProjectDirectory(),
                    workingDirectory: workingDirectory,
                    homeDirectory: homeDirectory,
                    additionalSearchPaths: resolveTemplateSearchPaths(),
                    fileManager: Self.fileManager,
                ).validate()
            } catch {
                throw ValidationError(error.localizedDescription)
            }
        }
    }
}
