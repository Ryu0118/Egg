import FileManagerProtocol
import Foundation

package struct OpenArgumentsValidator {
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

    package func validate() async throws -> OpenRunnerMode {
        guard let templateName else {
            return .interactive
        }

        guard let templatePath = try templatesFinder.validTemplateDirectory(templateName) else {
            throw Error.templateNotFound(name: templateName)
        }

        let templateLocation = TemplateLocation(homeDirectory: homeDirectory)
            .determineLocation(
                templateName: templateName,
                templatePath: templatePath,
                additionalSearchPaths: additionalSearchPaths,
                projectDirectory: projectDirectory,
                workingDirectory: workingDirectory,
            )

        return .direct(
            templateName: templateName,
            templatePath: templatePath,
            location: templateLocation,
        )
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
