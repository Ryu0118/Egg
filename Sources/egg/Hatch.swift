import Foundation
import ArgumentParser
import EggKit
import FileSystem

struct Hatch: AsyncParsableCommand, HasProjectDirectory {
    static let configuration = CommandConfiguration(
        commandName: "hatch",
        abstract: "Use a template to generate files with macro substitution."
    )

    @Argument(help: "The name of the template to use.")
    var templateName: String

    @Option(name: .long, help: "Directory to create the template in.", completion: .directory)
    var projectDirectory: String?

    @Option(name: .shortAndLong, help: "Output directory for the generated files. Defaults to current directory.")
    var output: String?

    @Argument(parsing: .captureForPassthrough, help: "User-defined macro values format (e.g., --user-defined value).")
    var macros: [String] = []

    static let fileSystem = FileSystem()

    mutating func run() async throws {
        let macros = try await validate()

        try await HatchRunner(macros: macros).run()
    }

    private func validate() async throws -> [EggMacro] {
        do {
            return try await HatchArgumentsValidator(
                templateName: templateName,
                macros: macros,
                projectDirectory: resolveProjectDirectory(),
                workingDirectory: Self.fileSystem.currentWorkingDirectory(),
                homeDirectory: FileManager.default.homeDirectoryForCurrentUser.absolutePath,
                fileSystem: Self.fileSystem
            ).validate()
        } catch {
            throw ValidationError(error.localizedDescription)
        }
    }
}
