import Foundation
import FileSystem
import Path
import Noora

package struct CreateRunner {
    private let mode: CreateRunnerMode
    private let templateLocation: TemplateLocation
    private let templateCreator: TemplateCreator

    package init(
        mode: CreateRunnerMode,
        skipConfig: Bool,
        projectDirectory: AbsolutePath,
        homeDirectory: AbsolutePath,
        fileSystem: some FileSysteming
    ) {
        let templateLocation = TemplateLocation(
            projectDirectory: projectDirectory,
            homeDirectory: homeDirectory
        )
        self.mode = mode
        self.templateLocation = templateLocation
        self.templateCreator = TemplateCreator(
            skipConfig: skipConfig,
            templateLocating: templateLocation,
            fileSystem: fileSystem,
        )
    }

    package func run() async throws {
        switch mode {
        case .noora:
            break
        case .provided(let name, let location):
            try await templateCreator.create(name, in: location)

            let templateDir = templateLocation.template(name, type: location)
            Noora().success("Successfully created template '\(name)' at \(templateDir.pathString)")
        }
    }
}

package enum CreateRunnerMode: Codable {
    case noora
    case provided(name: String, location: TemplateLocationType)
}
