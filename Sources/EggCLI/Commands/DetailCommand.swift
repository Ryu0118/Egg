import ArgumentParser
import EggKit
import FileManagerProtocol
import Foundation

package extension EggCommand.TemplateCommand {
    struct DetailCommand: AsyncParsableCommand, HasProjectDirectory, HasTemplateSearchPaths {
        package static let configuration = CommandConfiguration(
            commandName: "detail",
            abstract: "Show detailed information about a template.",
            discussion: """
            This command shows detailed information about a template, including:
            - Template name, description, and version
            - Location (global or project)
            - Required macros with their types, defaults, and validation rules
            - Example one-liner command for egg hatch

            Interactive Mode:
              When no template name is provided, you will be prompted to select a template.

            Direct Mode:
              Provide the template name as an argument.
              Example: egg template detail MyTemplate
            """,
        )

        @Argument(help: "The name of the template to show details for (optional for interactive mode).")
        package var templateName: String?

        @Option(name: .long, help: "Filter by location: 'global' or 'project'.", completion: .list(["global", "project"]))
        package var location: TemplateLocationType.Kind?

        @Option(name: .long, help: "Directory containing the template (defaults to current directory).", completion: .directory)
        package var projectDirectory: String?

        @Option(name: .long, parsing: .upToNextOption, help: "Additional directories to search for templates.", completion: .directory)
        package var templateSearchPaths: [String] = []

        package static let fileManager: any FileManagerProtocol = FileManager.default

        package init() {}

        package mutating func run() async throws {
            let mode = try await validate()
            do {
                let workingDirectory = URL(filePath: Self.fileManager.currentDirectoryPath)
                let homeDirectory = resolveHomeDirectory()
                try await DetailRunner(
                    mode: mode,
                    projectDirectory: resolveProjectDirectory(),
                    workingDirectory: workingDirectory,
                    homeDirectory: homeDirectory,
                    additionalSearchPaths: resolveTemplateSearchPaths(),
                    fileManager: Self.fileManager,
                ).run()
            } catch {
                printError(error.localizedDescription)
                throw ExitCode.failure
            }
        }

        func validate() async throws -> DetailRunnerMode {
            do {
                let workingDirectory = URL(filePath: Self.fileManager.currentDirectoryPath)
                let homeDirectory = resolveHomeDirectory()
                return try await DetailArgumentsValidator(
                    templateName: templateName,
                    location: location?.toConcreteType(
                        resolveProjectDirectory(),
                        workingDirectory: workingDirectory,
                    ),
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
