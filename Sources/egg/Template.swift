import Foundation
import ArgumentParser
import EggKit
import FileSystem
import Path
import Noora

struct Template: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "template",
        abstract: "Manage templates.",
        subcommands: [
            Create.self,
            List.self,
            Delete.self
        ]
    )
}

extension Template {
    struct Create: AsyncParsableCommand, HasProjectDirectory {
        static let configuration = CommandConfiguration(
            commandName: "create",
            abstract: "Create a new template with config.yml and template files."
        )

        @Option(name: .long, help: "Directory to create the template in.", completion: .directory)
        var projectDirectory: String?

        @Option(name: .long, help: "The name of the template to create.")
        var name: String?

        @Option(name: .long, help: "The description of the template to create.")
        var description: String?

        @Option(name: .long, help: "Where to store the template: 'global' or 'project' (current directory).", completion: .list(["global", "project"]))
        var location: TemplateLocationType?

        @Flag(name: .long, help: "Skip the creation of the config.yml file.")
        var skipConfig: Bool = false

        static let fileSystem = FileSystem()

        mutating func run() async throws {
            let mode = try await validate()
            do {
                try await CreateRunner(
                    mode: mode,
                    skipConfig: skipConfig,
                    projectDirectory: resolveProjectDirectory(),
                    workingDirectory: Self.fileSystem.currentWorkingDirectory(),
                    homeDirectory: FileManager.default.homeDirectoryForCurrentUser.absolutePath,
                    fileSystem: Self.fileSystem
                ).run()
            } catch {
                Noora().error("\(error.localizedDescription)")
            }
        }

        func validate() async throws -> CreateRunnerMode {
            do {
                return try await CreateArgumentsValidator(
                    name: name,
                    description: description,
                    location: location,
                    projectDirectory: try await resolveProjectDirectory(),
                    workingDirectory: Self.fileSystem.currentWorkingDirectory(),
                    homeDirectory: FileManager.default.homeDirectoryForCurrentUser.absolutePath,
                    fileSystem: Self.fileSystem
                ).validate()
            } catch {
                throw ValidationError(error.localizedDescription)
            }
        }
    }
}

extension Template {
    struct List: AsyncParsableCommand, HasProjectDirectory {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List all available templates."
        )

        @Option(name: .long, help: "Filter by location: 'global' or 'project'.", completion: .list(["global", "project"]))
        var location: TemplateLocationType?

        @Option(name: .long, help: "Directory to create the template in.", completion: .directory)
        var projectDirectory: String?

        static let fileSystem = FileSystem()

        mutating func run() async throws {
            let workingDirectory = try await Self.fileSystem.currentWorkingDirectory()
            try await ListRunner(
                location: location?.updatingProjectDirectory(AbsolutePath(validating: projectDirectory)?.relative(to: workingDirectory)),
                projectDirectory: resolveProjectDirectory(),
                workingDirectory: workingDirectory,
                homeDirectory: FileManager.default.homeDirectoryForCurrentUser.absolutePath,
                fileSystem: Self.fileSystem
            ).run()
        }
    }
}

extension AbsolutePath {
    init?(validating: String?) throws {
        if let validating {
            try self.init(validating: validating)
        }
        return nil
    }
}

extension Template {
    struct Delete: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "delete",
            abstract: "Delete a template."
        )

        @Argument(help: "The name of the template to delete (optional for interactive mode).")
        var templateName: String?

        @Option(name: .long, help: "Specify location: 'global' or 'project'.", completion: .list(["global", "project"]))
        var location: TemplateLocationType?

        private static let fileSystem = FileSystem()

        mutating func run() async throws {
            // TODO: Implement delete functionality
            print("Template delete command - to be implemented")
        }
    }
}

protocol HasProjectDirectory {
    var projectDirectory: String? { get }
    static var fileSystem: FileSystem { get }
}

extension HasProjectDirectory {
    func resolveProjectDirectory() async throws -> AbsolutePath {
        if let projectDirectory {
            try await AbsolutePath(validating: projectDirectory, relativeTo: Self.fileSystem.currentWorkingDirectory())
        } else {
            try await Self.fileSystem.currentWorkingDirectory()
        }
    }
}

extension TemplateLocationType: ExpressibleByArgument {
    package init?(argument: String) {
        self.init(rawValue: argument)
    }
}
