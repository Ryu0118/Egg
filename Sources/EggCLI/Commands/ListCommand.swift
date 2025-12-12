import ArgumentParser
import EggKit
import FileManagerProtocol
import Foundation

package extension EggCommand.TemplateCommand {
    struct ListCommand: AsyncParsableCommand, HasProjectDirectory {
        package static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List all available templates."
        )

        @Option(name: .long, help: "Filter by location: 'global' or 'project'.", completion: .list(["global", "project"]))
        package var location: TemplateLocationType.Kind?

        @Option(name: .long, help: "Directory to list templates from (defaults to current directory).", completion: .directory)
        package var projectDirectory: String?

        @Flag(name: .long, help: "Hide the description column in the output.")
        package var hideDescription: Bool = false

        package static let fileManager: any FileManagerProtocol = FileManager.default

        package init() {}

        package mutating func run() async throws {
            let workingDirectory = URL(filePath: Self.fileManager.currentDirectoryPath)
            let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
            try await ListRunner(
                location: location?.toConcreteType(
                    resolveProjectDirectory(),
                    workingDirectory: workingDirectory
                ),
                projectDirectory: resolveProjectDirectory(),
                workingDirectory: workingDirectory,
                homeDirectory: homeDirectory,
                fileManager: Self.fileManager,
                hideDescription: hideDescription
            ).run()
        }
    }
}
