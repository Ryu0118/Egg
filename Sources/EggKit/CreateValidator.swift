import Foundation
import Path
import FileSystem

package struct CreateValidator {
    private let name: String?
    private let location: TemplateLocationType?
    private let templatesFinder: TemplatesFinder

    package init(
        name: String?,
        location: TemplateLocationType?,
        projectDirectory: AbsolutePath,
        homeDirectory: AbsolutePath,
        fileSystem: some FileSysteming
    ) {
        self.name = name
        self.location = location
        self.templatesFinder = TemplatesFinder(
            fileSystem: fileSystem,
            projectDirectory: projectDirectory,
            homeDirectory: homeDirectory
        )
    }

    package func validate() async throws -> CreateRunnerMode {
        // Both nil means interactive mode (Noora)
        if name == nil && location == nil {
            return .noora
        }

        // Both must be provided together
        guard let name else {
            throw Error.nameRequired
        }
        guard let location else {
            throw Error.locationRequired
        }
        guard !(try await templatesFinder.exists(name)) else {
            throw Error.templateAlreadyExists
        }

        return .provided(name: name, location: location)
    }

    enum Error: LocalizedError {
        case nameRequired
        case locationRequired
        case templateAlreadyExists

        var errorDescription: String? {
            switch self {
            case .nameRequired:
                "Template name is required when location is specified"
            case .locationRequired:
                "Template location is required when name is specified"
            case .templateAlreadyExists:
                "A template with the same name already exists"
            }
        }
    }
}
