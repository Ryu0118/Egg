import FileManagerProtocol
import Foundation

package struct MoveArgumentsValidator {
    private let templateName: String?
    private let to: TemplateLocationType.Kind?
    private let force: Bool
    private let templatesFinder: TemplatesFinder
    private let homeDirectory: URL
    private let projectDirectory: URL
    private let workingDirectory: URL
    private let fileManager: any FileManagerProtocol

    package init(
        templateName: String?,
        to: TemplateLocationType.Kind?,
        force: Bool,
        projectDirectory: URL,
        workingDirectory: URL,
        homeDirectory: URL,
        fileManager: some FileManagerProtocol
    ) {
        self.templateName = templateName
        self.to = to
        self.force = force
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

    package func validate() async throws -> MoveRunnerMode {
        // No template name -> fully interactive
        guard let templateName else {
            return .interactive
        }

        // Find the template
        guard let sourcePath = try templatesFinder.validTemplateDirectory(templateName) else {
            throw Error.templateNotFound(name: templateName)
        }

        // Determine source location
        let sourceLocation = determineLocation(templateName: templateName, path: sourcePath)

        // No target -> select target only
        guard let to else {
            return .selectTarget(
                name: templateName,
                path: sourcePath.path(percentEncoded: false),
                sourceLocation: sourceLocation
            )
        }

        // Convert Kind to concrete TemplateLocationType
        let targetLocation = to.toConcreteType(projectDirectory, workingDirectory: workingDirectory)

        // Validate the move
        try validateMove(
            templateName: templateName,
            sourceLocation: sourceLocation,
            targetLocation: targetLocation
        )

        return .direct(
            name: templateName,
            path: sourcePath.path(percentEncoded: false),
            sourceLocation: sourceLocation,
            targetLocation: targetLocation
        )
    }

    private func determineLocation(
        templateName: String,
        path: URL
    ) -> TemplateLocationType {
        let templateLocationInstance = TemplateLocation(
            homeDirectory: homeDirectory
        )
        let globalPath = templateLocationInstance.template(templateName, type: .global)

        return if fileManager.fileExists(atPath: globalPath.path(percentEncoded: false)) && path == globalPath {
            TemplateLocationType.global
        } else {
            TemplateLocationType.project(
                projectDirectory,
                workingDirectory: workingDirectory
            )
        }
    }

    private func validateMove(
        templateName: String,
        sourceLocation: TemplateLocationType,
        targetLocation: TemplateLocationType
    ) throws {
        // Check if source and target are the same
        if sourceLocation.name == targetLocation.name {
            throw Error.sameLocation(name: templateName, location: sourceLocation.name)
        }

        // Check if target already exists (unless force is true)
        if !force {
            let templateLocationInstance = TemplateLocation(homeDirectory: homeDirectory)
            let targetPath = templateLocationInstance.template(templateName, type: targetLocation)
            if fileManager.fileExists(atPath: targetPath.path(percentEncoded: false)) {
                throw Error.targetAlreadyExists(name: templateName, location: targetLocation.name)
            }
        }
    }

    enum Error: LocalizedError {
        case templateNotFound(name: String)
        case sameLocation(name: String, location: String)
        case targetAlreadyExists(name: String, location: String)

        var errorDescription: String? {
            switch self {
            case let .templateNotFound(name):
                return "Template '\(name)' not found"
            case let .sameLocation(name, location):
                return "Template '\(name)' is already in \(location)"
            case let .targetAlreadyExists(name, location):
                return "Template '\(name)' already exists in \(location). Use --force to overwrite"
            }
        }
    }
}
