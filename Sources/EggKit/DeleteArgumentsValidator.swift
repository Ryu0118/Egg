import Foundation
import Path
import FileSystem

package struct DeleteArgumentsValidator {
    private let templateName: String?
    private let templatesFinder: TemplatesFinder
    private let homeDirectory: AbsolutePath
    private let projectDirectory: AbsolutePath
    private let workingDirectory: AbsolutePath

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
        self.templatesFinder = TemplatesFinder(
            fileSystem: fileSystem,
            projectDirectory: projectDirectory,
            workingDirectory: workingDirectory,
            homeDirectory: homeDirectory
        )
    }

    package func validate() async throws -> DeleteRunnerMode {
        // templateName is nil means interactive mode (Noora)
        guard let templateName else {
            return .noora
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
        let templateLocation: TemplateLocationType
        if try await templatesFinder.fileSystem.exists(globalPath) && path == globalPath {
            templateLocation = .global
        } else {
            templateLocation = .project(
                projectDirectory,
                workingDirectory: workingDirectory
            )
        }

        return .provided(name: templateName, path: path.pathString, location: templateLocation)
    }

    enum Error: LocalizedError {
        case templateNotFound(name: String)

        var errorDescription: String? {
            switch self {
            case .templateNotFound(let name):
                return "Template '\(name)' not found"
            }
        }
    }
}
