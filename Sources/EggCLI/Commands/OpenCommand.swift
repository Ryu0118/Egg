import ArgumentParser
import EggKit
import FileManagerProtocol
import Foundation
import Noora
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

        package static let fileManager: any FileManagerProtocol = FileManager.default

        package init() {}

        package mutating func run() async throws {
            let mode = try await validate()
            do {
                let workingDirectory = URL(filePath: Self.fileManager.currentDirectoryPath)
                let homeDirectory = resolveHomeDirectory()
                try await OpenRunner(
                    mode: mode,
                    processRunner: ProcessRunner(),
                    projectDirectory: await resolveProjectDirectory(),
                    workingDirectory: workingDirectory,
                    homeDirectory: homeDirectory,
                    fileManager: Self.fileManager
                ).run()
            } catch {
                Noora().error("\(error.localizedDescription)")
            }
        }

        func validate() async throws -> OpenRunnerMode {
            do {
                let workingDirectory = URL(filePath: Self.fileManager.currentDirectoryPath)
                let homeDirectory = resolveHomeDirectory()
                return try await OpenArgumentsValidator(
                    templateName: templateName,
                    projectDirectory: await resolveProjectDirectory(),
                    workingDirectory: workingDirectory,
                    homeDirectory: homeDirectory,
                    fileManager: Self.fileManager
                ).validate()
            } catch {
                throw ValidationError(error.localizedDescription)
            }
        }
    }
}
