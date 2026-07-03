import ArgumentParser
import EggKit
import FileManagerProtocol
import Foundation

package extension EggCommand.TemplateCommand {
    struct ListCommand: AsyncParsableCommand, HasProjectDirectory, HasTemplateSearchPaths {
        @Flag(name: .long, help: "Hide the description column in the output.")
        package var hideDescription: Bool = false

        @Option(name: .long, help: "Filter by location: 'global' or 'project'.", completion: .list(["global", "project"]))
        package var location: TemplateLocationType.Kind?

        @Option(name: .long, help: "Directory to list templates from (defaults to current directory).", completion: .directory)
        package var projectDirectory: String?

        @Option(name: .long, parsing: .upToNextOption, help: "Additional directories to search for templates.", completion: .directory)
        package var templateSearchPaths: [String] = []
        package static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List all available templates.",
        )

        package static let fileManager: any FileManagerProtocol = FileManager.default

        package init() {}

        package mutating func run() async throws {
            let workingDirectory = URL(filePath: Self.fileManager.currentDirectoryPath)
            let homeDirectory = CLIEnvironment.resolveHomeDirectory()
            try await ListRunner(
                location: location?.toConcreteType(
                    resolveProjectDirectory(),
                    workingDirectory: workingDirectory,
                ),
                projectDirectory: resolveProjectDirectory(),
                workingDirectory: workingDirectory,
                homeDirectory: homeDirectory,
                additionalSearchPaths: resolveTemplateSearchPaths(),
                fileManager: Self.fileManager,
                hideDescription: hideDescription,
            ).run()
        }
    }
}
