import Foundation
import ArgumentParser
import EggKit
import FileSystem

struct Hatch: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "hatch",
        abstract: "Use a template to generate files with macro substitution."
    )

    @Argument(help: "The name of the template to use.")
    var templateName: String

    @Option(name: .shortAndLong, help: "Output directory for the generated files. Defaults to current directory.")
    var output: String?

    @Argument(parsing: .captureForPassthrough, help: "User-defined macro values format (e.g., --user-defined value).")
    var macros: [String] = []

    private static let fileSystem = FileSystem()

    mutating func run() async throws {
        let macros = try await validate()

        try await HatchRunner(macros: macros).run()
    }

    private func validate() async throws -> [EggMacro] {
        do {
            return try await HatchArgumentsValidator(
                templateName: templateName,
                macros: macros,
                projectDirectory: Self.fileSystem.currentWorkingDirectory(),
                homeDirectory: FileManager.default.homeDirectoryForCurrentUser.absolutePath,
                fileSystem: Self.fileSystem
            ).validate()
        } catch {
            throw ValidationError(error.localizedDescription)
        }
    }
}
