import ArgumentParser
import EggKit
import FileSystem
import Foundation
import Noora
import Path
import ProcessRunning

struct TemplateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "template",
        abstract: "Manage templates.",
        subcommands: [
            CreateCommand.self,
            ListCommand.self,
            DeleteCommand.self,
            DuplicateCommand.self,
            OpenCommand.self,
        ]
    )
}

extension TemplateCommand {
    struct CreateCommand: AsyncParsableCommand, HasProjectDirectory {
        static let configuration = CommandConfiguration(
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
        var projectDirectory: String?

        @Option(name: .long, help: "The name of the template to create.")
        var name: String?

        @Option(name: .long, help: "The description of the template to create.")
        var description: String?

        @Option(
            name: .long,
            help: "Where to store the template: 'global' or 'project' (current directory).",
            completion: .list(["global", "project"])
        )
        var location: TemplateLocationType.Kind?

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
                let projectDirectory = try await resolveProjectDirectory()
                let workingDirectory = try await Self.fileSystem.currentWorkingDirectory()
                return try await CreateArgumentsValidator(
                    name: name,
                    description: description,
                    location: location,
                    projectDirectory: projectDirectory,
                    workingDirectory: workingDirectory,
                    homeDirectory: FileManager.default.homeDirectoryForCurrentUser.absolutePath,
                    fileSystem: Self.fileSystem
                ).validate()
            } catch {
                throw ValidationError(error.localizedDescription)
            }
        }
    }
}

extension TemplateCommand {
    struct ListCommand: AsyncParsableCommand, HasProjectDirectory {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List all available templates."
        )

        @Option(name: .long, help: "Filter by location: 'global' or 'project'.", completion: .list(["global", "project"]))
        var location: TemplateLocationType.Kind?

        @Option(name: .long, help: "Directory to list templates from (defaults to current directory).", completion: .directory)
        var projectDirectory: String?

        @Flag(name: .long, help: "Hide the description column in the output.")
        var hideDescription: Bool = false

        static let fileSystem = FileSystem()

        mutating func run() async throws {
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

extension AbsolutePath {
    init?(validating: String?) throws {
        if let validating {
            try self.init(validating: validating)
        }
        return nil
    }
}

extension TemplateCommand {
    struct DeleteCommand: AsyncParsableCommand, HasProjectDirectory {
        static let configuration = CommandConfiguration(
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
            """
        )

        @Argument(help: "The name of the template to delete (optional for interactive mode).")
        var templateName: String?

        @Option(name: .long, help: "Directory containing the template to delete (defaults to current directory).", completion: .directory)
        var projectDirectory: String?

        @Option(name: .long, help: "Delete the template without confirmation.")
        var force: Bool = false

        static let fileSystem = FileSystem()

        mutating func run() async throws {
            let mode = try await validate()
            do {
                try await DeleteRunner(
                    mode: mode,
                    force: force,
                    projectDirectory: await resolveProjectDirectory(),
                    workingDirectory: await Self.fileSystem.currentWorkingDirectory(),
                    homeDirectory: FileManager.default.homeDirectoryForCurrentUser.absolutePath,
                    fileSystem: Self.fileSystem
                ).run()
            } catch {
                Noora().error("\(error.localizedDescription)")
            }
        }

        func validate() async throws -> DeleteRunnerMode {
            do {
                return try await DeleteArgumentsValidator(
                    templateName: templateName,
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

extension TemplateCommand {
    struct DuplicateCommand: AsyncParsableCommand, HasProjectDirectory {
        static let configuration = CommandConfiguration(
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
        var templateName: String?

        @Option(name: .long, help: "The name for the duplicated template.")
        var name: String?

        @Option(name: .long, help: "The description for the duplicated template.")
        var description: String?

        @Option(name: .long, help: "Directory containing the template to duplicate (defaults to current directory).", completion: .directory)
        var projectDirectory: String?

        static let fileSystem = FileSystem()

        mutating func run() async throws {
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

extension TemplateCommand {
    struct OpenCommand: AsyncParsableCommand, HasProjectDirectory {
        static let configuration = CommandConfiguration(
            commandName: "open",
            abstract: "Open a template directory in Finder.",
            discussion: """
            This command supports two modes:

            Interactive Mode:
              When no template name is provided, you will be prompted to:
              - Select a template from the available templates

            Direct Mode:
              Provide the template name as an argument.
              Example: egg template open MyTemplate
            """
        )

        @Argument(help: "The name of the template to open (optional for interactive mode).")
        var templateName: String?

        @Option(name: .long, help: "Directory containing the template to open (defaults to current directory).", completion: .directory)
        var projectDirectory: String?

        static let fileSystem = FileSystem()

        mutating func run() async throws {
            let mode = try await validate()
            do {
                let workingDirectory = try await Self.fileSystem.currentWorkingDirectory()
                try await OpenRunner(
                    mode: mode,
                    processRunner: ProcessRunner(),
                    projectDirectory: await resolveProjectDirectory(),
                    workingDirectory: workingDirectory,
                    homeDirectory: FileManager.default.homeDirectoryForCurrentUser.absolutePath,
                    fileSystem: Self.fileSystem
                ).run()
            } catch {
                Noora().error("\(error.localizedDescription)")
            }
        }

        func validate() async throws -> OpenRunnerMode {
            do {
                return try await OpenArgumentsValidator(
                    templateName: templateName,
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

extension TemplateLocationType.Kind: ExpressibleByArgument {}
