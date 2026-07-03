import ArgumentParser
import EggKit
import FileManagerProtocol
import Foundation

package extension EggCommand.TemplateCommand {
    struct ValidateCommand: AsyncParsableCommand, HasProjectDirectory {
        @Argument(help: "Path to the template directory containing config.yml.")
        package var templatePath: String

        @Option(name: .long, help: "Directory containing the template (defaults to current directory).", completion: .directory)
        package var projectDirectory: String?
        package static let configuration = CommandConfiguration(
            commandName: "validate",
            abstract: "Validate a template's config.yml file.",
            discussion: """
            This command validates a template's config.yml file to ensure it is properly formatted
            and meets all requirements.

            Example: egg template validate path/to/template
            """,
        )

        package static let fileManager: any FileManagerProtocol = FileManager.default

        package init() {}

        package mutating func run() async throws {
            let mode = try await validate()
            do {
                try await ValidateRunner(
                    mode: mode,
                    fileManager: Self.fileManager,
                ).run()
            } catch {
                CLIOutput.printError(error.localizedDescription)
                throw ExitCode.failure
            }
        }

        func validate() async throws -> ValidateRunnerMode {
            do {
                return try await ValidateArgumentsValidator(
                    templatePath: templatePath,
                    fileManager: Self.fileManager,
                ).validate()
            } catch {
                throw ValidationError(error.localizedDescription)
            }
        }
    }
}
