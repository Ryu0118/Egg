import ArgumentParser
import EggKit
import FileSystem
import Foundation
import Noora
import Path
import ProcessRunning

package extension EggCommand.TemplateCommand {
    struct OpenCommand: AsyncParsableCommand, HasProjectDirectory {
        package static let configuration = CommandConfiguration(
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
        package var templateName: String?

        @Option(name: .long, help: "Directory containing the template to open (defaults to current directory).", completion: .directory)
        package var projectDirectory: String?

        package static let fileSystem = FileSystem()

        package init() {}

        package mutating func run() async throws {
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
