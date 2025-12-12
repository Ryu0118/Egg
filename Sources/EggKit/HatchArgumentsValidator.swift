import FileManagerProtocol
import Foundation

package struct HatchArgumentsValidator {
    private let templateName: String?
    private let macros: [String]
    private let templateFinder: TemplatesFinder
    private let parser: MacrosParser

    package init(
        templateName: String?,
        macros: [String],
        projectDirectory: URL,
        workingDirectory: URL,
        homeDirectory: URL,
        fileManager: some FileManagerProtocol
    ) {
        self.templateName = templateName
        self.macros = macros
        templateFinder = TemplatesFinder(
            fileManager: fileManager,
            projectDirectory: projectDirectory,
            workingDirectory: workingDirectory,
            homeDirectory: homeDirectory
        )
        parser = MacrosParser()
    }

    package func validate() async throws -> HatchRunnerMode {
        // templateName is nil means interactive mode
        guard let templateName else {
            return .interactive
        }

        let parsedMacros = try parser.parseCommandLineArguments(macros)

        let template = try await templateFinder.fetchTemplate(templateName)

        // Perform basic validation (without path resolution)
        // Path resolution will be done by the workflow runner after staging area creation
        let validator = ParsedMacroBasicValidator(config: template.config)
        try validator.validate(parsedMacros)

        return .direct(template: template, parsedMacros: parsedMacros)
    }
}

package enum HatchRunnerMode {
    case interactive
    case direct(template: Template, parsedMacros: [ParsedMacroDefinition])
}
