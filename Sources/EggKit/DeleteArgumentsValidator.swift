import FileManagerProtocol
import Foundation

package struct DeleteArgumentsValidator {
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

    package func validate() async throws -> DeleteRunnerMode {
        // templateName is nil means interactive mode
        guard let templateName else {
            return .interactive
        }

        // Check in both locations
        guard let path = try await templatesFinder.validTemplateDirectory(templateName) else {
            throw Error.templateNotFound(name: templateName)
        }

        // Determine which location it's in
        let templateLocationInstance = TemplateLocation(
            homeDirectory: homeDirectory
        )
        let globalPath = templateLocationInstance.template(templateName, type: .global)
        let templateLocation = if fileManager.fileExists(atPath: globalPath.path) && path == globalPath {
            TemplateLocationType.global
        } else {
            TemplateLocationType.project(
                projectDirectory,
                workingDirectory: workingDirectory
            )
        }

        return .direct(name: templateName, path: path.path, location: templateLocation)
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
