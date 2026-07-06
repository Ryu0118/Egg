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

        @Flag(name: .long, help: "Emit machine-readable JSON on stdout instead of the human-readable output.")
        package var json = false

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
            if json {
                let result = try await EggService(
                    fileManager: Self.fileManager,
                    projectDirectory: resolveProjectDirectory(),
                    homeDirectory: CLIEnvironment.resolveHomeDirectory(),
                ).validateTemplate(templatePath: templatePath)
                try CLIOutput.printJSON(result)
                // Same failure signal as the human mode: a caller that only
                // checks the exit code must not read an invalid template as
                // success just because it asked for JSON.
                guard result.isValid else {
                    throw ExitCode.failure
                }
                return
            }
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
                // A broken template is a validation *result*, not a usage
                // mistake: report it plainly and exit 1. Wrapping in
                // ArgumentParser's ValidationError printed the command usage
                // and exited 64, burying the actual problem.
                CLIOutput.printError(error.localizedDescription)
                throw ExitCode.failure
            }
        }
    }
}
