import ArgumentParser
import EggKit
import FileSystem
import Foundation
import Path

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

        package static let fileSystem = FileSystem()

        package init() {}

        package mutating func run() async throws {
            let workingDirectory = try await Self.fileSystem.currentWorkingDirectory()
            try await ListRunner(
                location: location?.toConcreteType(
                    resolveProjectDirectory(),
                    workingDirectory: workingDirectory
                ),
                projectDirectory: resolveProjectDirectory(),
                workingDirectory: workingDirectory,
                homeDirectory: FileManager.default.homeDirectoryForCurrentUser.absolutePath,
                fileSystem: Self.fileSystem,
                hideDescription: hideDescription
            ).run()
        }
    }
}
