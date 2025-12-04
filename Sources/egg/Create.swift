import Foundation
import ArgumentParser
import EggKit
import FileSystem
import Path

struct Create: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Create a new template with config.yml and template files."
    )

    @Option(name: .long, help: "Directory to create the template in.", completion: .directory)
    var projectDirectory: String?

    @Option(name: .long, help: "The name of the template to create.")
    var name: String?

    @Option(name: .long, help: "Where to store the template: 'global' or 'project' (current directory).", completion: .list(["global", "project"]))
    var location: TemplateLocationType?

    @Flag(name: .long, help: "Skip the creation of the config.yml file.")
    var skipConfig: Bool = false

    private static let fileSystem = FileSystem()

    mutating func run() async throws {
        let mode = try await validate()
        try await CreateRunner(
            mode: mode,
            skipConfig: skipConfig,
            projectDirectory: resolveProjectDirectory(),
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser.absolutePath,
            fileSystem: Self.fileSystem
        ).run()
    }

    func resolveProjectDirectory() async throws -> AbsolutePath {
        if let projectDirectory {
            try await AbsolutePath(validating: projectDirectory, relativeTo: Self.fileSystem.currentWorkingDirectory())
        } else {
            try await Self.fileSystem.currentWorkingDirectory()
        }
    }

    func validate() async throws -> CreateRunnerMode {
        do {
            return try await CreateValidator(
                name: name,
                location: location,
                currentDirectory: Self.fileSystem.currentWorkingDirectory(),
                homeDirectory: FileManager.default.homeDirectoryForCurrentUser.absolutePath,
                fileSystem: Self.fileSystem
            ).validate()
        } catch {
            throw ValidationError(error.localizedDescription)
        }
    }
}

extension TemplateLocationType: ExpressibleByArgument {}
