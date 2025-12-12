import FileManagerProtocol
import Foundation

package struct OpenArgumentsValidator {
    private let templateName: String?
    private let templatesFinder: TemplatesFinder
    private let homeDirectory: URL
    private let projectDirectory: URL
    private let workingDirectory: URL
    private let fileManager: any FileManagerProtocol

    package init(
        templateName: String?,
        projectDirectory: URL,
        workingDirectory: URL,
        homeDirectory: URL,
        fileManager: some FileManagerProtocol
    ) {
        self.templateName = templateName
        self.homeDirectory = homeDirectory
        self.projectDirectory = projectDirectory
        self.workingDirectory = workingDirectory
        self.fileManager = fileManager
        templatesFinder = TemplatesFinder(
            fileManager: fileManager,
            projectDirectory: projectDirectory,
            workingDirectory: workingDirectory,
            homeDirectory: homeDirectory
        )
    }

    package func validate() async throws -> OpenRunnerMode {
        guard let templateName else {
            return .interactive
        }

        let (templatePath, templateLocation) = try await findTemplate(name: templateName)

        return .direct(
            templateName: templateName,
            templatePath: templatePath,
            location: templateLocation
        )
    }

    private func findTemplate(
        name: String
    ) async throws -> (path: URL, location: TemplateLocationType) {
        guard let templatePath = try await templatesFinder.validTemplateDirectory(name) else {
            throw Error.templateNotFound(name: name)
        }

        let templateLocation = try determineLocation(
            templateName: name,
            templatePath: templatePath
        )

        return (templatePath, templateLocation)
    }

    private func determineLocation(
        templateName: String,
        templatePath: URL
    ) throws -> TemplateLocationType {
        let templateLocationInstance = TemplateLocation(
            homeDirectory: homeDirectory
        )
        let globalPath = templateLocationInstance.template(templateName, type: .global)

        return if fileManager.exists(globalPath) && templatePath == globalPath {
            TemplateLocationType.global
        } else {
            TemplateLocationType.project(
                projectDirectory,
                workingDirectory: workingDirectory
            )
        }
    }

    enum Error: LocalizedError {
        case templateNotFound(name: String)

        var errorDescription: String? {
            switch self {
            case let .templateNotFound(name):
                return "Template '\(name)' not found"
            }
        }
    }
}
