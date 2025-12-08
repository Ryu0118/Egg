import FileSystem
import Foundation
import Path

package struct OpenArgumentsValidator {
    private let templateName: String?
    private let templatesFinder: TemplatesFinder
    private let homeDirectory: AbsolutePath
    private let projectDirectory: AbsolutePath
    private let workingDirectory: AbsolutePath
    private let fileSystem: any FileSysteming

    package init(
        templateName: String?,
        projectDirectory: AbsolutePath,
        workingDirectory: AbsolutePath,
        homeDirectory: AbsolutePath,
        fileSystem: some FileSysteming
    ) {
        self.templateName = templateName
        self.homeDirectory = homeDirectory
        self.projectDirectory = projectDirectory
        self.workingDirectory = workingDirectory
        self.fileSystem = fileSystem
        templatesFinder = TemplatesFinder(
            fileSystem: fileSystem,
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
    ) async throws -> (path: AbsolutePath, location: TemplateLocationType) {
        guard let templatePath = try await templatesFinder.validTemplateDirectory(name) else {
            throw Error.templateNotFound(name: name)
        }

        let templateLocation = try await determineLocation(
            templateName: name,
            templatePath: templatePath
        )

        return (templatePath, templateLocation)
    }

    private func determineLocation(
        templateName: String,
        templatePath: AbsolutePath
    ) async throws -> TemplateLocationType {
        let templateLocationInstance = TemplateLocation(
            homeDirectory: homeDirectory
        )
        let globalPath = templateLocationInstance.template(templateName, type: .global)

        return if try await fileSystem.exists(globalPath) && templatePath == globalPath {
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
