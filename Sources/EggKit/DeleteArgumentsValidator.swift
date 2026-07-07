import FileManagerProtocol
import Foundation

package struct DeleteArgumentsValidator {
    private let templateName: String?
    private let templatesFinder: TemplatesFinder
    private let homeDirectory: URL
    private let projectDirectory: URL
    private let workingDirectory: URL
    private let additionalSearchPaths: [URL]
    private let fileManager: any FileManagerProtocol

    package init(
        templateName: String?,
        projectDirectory: URL,
        workingDirectory: URL,
        homeDirectory: URL,
        additionalSearchPaths: [URL] = [],
        fileManager: some FileManagerProtocol,
    ) {
        self.templateName = templateName
        self.homeDirectory = homeDirectory
        self.projectDirectory = projectDirectory
        self.workingDirectory = workingDirectory
        self.additionalSearchPaths = additionalSearchPaths
        self.fileManager = fileManager
        templatesFinder = TemplatesFinder(
            fileManager: fileManager,
            projectDirectory: projectDirectory,
            workingDirectory: workingDirectory,
            homeDirectory: homeDirectory,
            additionalSearchPaths: additionalSearchPaths,
        )
    }

    package func validate() async throws -> DeleteRunnerMode {
        // templateName is nil means interactive mode
        guard let templateName else {
            return .interactive
        }

        // Check in all locations (custom, global, project)
        guard let path = try await templatesFinder.validTemplateDirectory(templateName) else {
            throw Error.templateNotFound(name: templateName)
        }

        // Determine which location it's in
        let templateLocation = TemplateLocation(homeDirectory: homeDirectory)
            .determineLocation(
                templateName: templateName,
                templatePath: path,
                additionalSearchPaths: additionalSearchPaths,
                projectDirectory: projectDirectory,
                workingDirectory: workingDirectory,
            )

        // Block deletion from custom paths
        if templateLocation.isCustom {
            throw Error.cannotDeleteFromCustomPath(name: templateName)
        }

        return .direct(name: templateName, path: path.path, location: templateLocation)
    }

    enum Error: LocalizedError {
        case templateNotFound(name: String)
        case cannotDeleteFromCustomPath(name: String)

        var errorDescription: String? {
            switch self {
            case let .templateNotFound(name):
                "Template '\(name)' not found"
            case let .cannotDeleteFromCustomPath(name):
                "Cannot delete template '\(name)' from custom search path. Templates in custom paths are read-only."
            }
        }
    }
}
