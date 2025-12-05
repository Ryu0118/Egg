import Foundation
import FileSystem
import Path

package struct HatchArgumentsValidator {
    private let templateName: String
    private let macros: [String]
    private let templateFinder: TemplatesFinder
    private let parser: EggMacrosParser

    package init(
        templateName: String,
        macros: [String],
        projectDirectory: AbsolutePath,
        homeDirectory: AbsolutePath,
        fileSystem: sending some FileSysteming
    ) {
        self.templateName = templateName
        self.macros = macros
        self.templateFinder = TemplatesFinder(
            fileSystem: fileSystem,
            projectDirectory: projectDirectory,
            homeDirectory: homeDirectory
        )
        self.parser = EggMacrosParser()
    }

    package func validate() async throws -> [EggMacro] {
        guard try await templateFinder.exists(templateName) else {
            throw Error.templateNotFound(name: templateName)
        }
        return try parser.parse(macros)
    }

    enum Error: LocalizedError {
        case templateNotFound(name: String)

        var errorDescription: String? {
            switch self {
            case .templateNotFound(let name):
                "Template '\(name)' not found."
            }
        }
    }
}
