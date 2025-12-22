import FileManagerProtocol
import Foundation

package struct DetailArgumentsValidator {
    private let templateName: String?
    private let location: TemplateLocationType?
    private let templatesFinder: TemplatesFinder
    private let homeDirectory: URL
    private let projectDirectory: URL
    private let workingDirectory: URL
    private let fileManager: any FileManagerProtocol

    package init(
        templateName: String?,
        location: TemplateLocationType?,
        projectDirectory: URL,
        workingDirectory: URL,
        homeDirectory: URL,
        fileManager: some FileManagerProtocol
    ) {
        self.templateName = templateName
        self.location = location
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

    package func validate() async throws -> DetailRunnerMode {
        guard let templateName else {
            return .interactive(location: location)
        }

        let template = try await templatesFinder.fetchTemplate(templateName)
        let templateLocation = try determineLocation(
            templateName: templateName,
            templatePath: template.path
        )

        return .direct(
            template: template,
            location: templateLocation
        )
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
                "Template '\(name)' not found"
            }
        }
    }
}

package enum DetailRunnerMode: Equatable {
    case interactive(location: TemplateLocationType?)
    case direct(template: Template, location: TemplateLocationType)
}
