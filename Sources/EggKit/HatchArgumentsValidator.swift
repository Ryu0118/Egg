import FileSystem
import Foundation
import Path

package struct HatchArgumentsValidator {
    private let templateName: String?
    private let macros: [String]
    private let templateFinder: TemplatesFinder
    private let parser: MacrosParser
    private let workingDirectory: AbsolutePath
    private let homeDirectory: AbsolutePath

    package init(
        templateName: String?,
        macros: [String],
        projectDirectory: AbsolutePath,
        workingDirectory: AbsolutePath,
        homeDirectory: AbsolutePath,
        fileSystem: some FileSysteming
    ) {
        self.templateName = templateName
        self.macros = macros
        templateFinder = TemplatesFinder(
            fileSystem: fileSystem,
            projectDirectory: projectDirectory,
            workingDirectory: workingDirectory,
            homeDirectory: homeDirectory
        )
        self.workingDirectory = workingDirectory
        self.homeDirectory = homeDirectory
        parser = MacrosParser()
    }

    package func validate() async throws -> HatchRunnerMode {
        // templateName is nil means interactive mode
        guard let templateName else {
            return .interactive
        }

        let parsedMacros = try parser.parseCommandLineArguments(macros)

        let template = try await templateFinder.fetchTemplate(templateName)

        let validator = ParsedMacroDefinitionValidator(
            config: template.config,
            workingDirectory: workingDirectory,
            homeDirectory: homeDirectory
        )

        let resolvedMacros = try validator.validate(parsedMacros)
        print(resolvedMacros)
        return .direct(template: template, macros: resolvedMacros)
    }
}

package enum HatchRunnerMode {
    case interactive
    case direct(template: Template, macros: [ResolvedMacro])
}
