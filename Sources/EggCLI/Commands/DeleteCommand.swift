import ArgumentParser
import EggKit
import FileManagerProtocol
import Foundation

package extension EggCommand.TemplateCommand {
    struct DeleteCommand: AsyncParsableCommand, HasProjectDirectory, HasTemplateSearchPaths {
        @Argument(help: "The name of the template to delete (optional for interactive mode).")
        package var templateName: String?

        @Flag(name: .long, help: "Delete the template without confirmation.")
        package var force: Bool = false

        @Option(name: .long, help: "Directory containing the template to delete (defaults to current directory).", completion: .directory)
        package var projectDirectory: String?

        @Option(name: .long, parsing: .upToNextOption, help: "Additional directories to search for templates.", completion: .directory)
        package var templateSearchPaths: [String] = []
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
            """,
        )

        package static let fileManager: any FileManagerProtocol = FileManager.default

        package init() {}

        package mutating func run() async throws {
            let mode = try await validate()
            do {
                try await DeleteRunner(
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

        func validate() async throws -> DeleteRunnerMode {
            do {
                let projectDirectory = try await resolveProjectDirectory()
                let workingDirectory = URL(filePath: Self.fileManager.currentDirectoryPath)
                return try await DeleteArgumentsValidator(
                    templateName: templateName,
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
