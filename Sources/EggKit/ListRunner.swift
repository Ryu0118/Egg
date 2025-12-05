import Foundation
import FileSystem
import Path
import Noora

package struct ListRunner {
    let location: TemplateLocationType?
    let finder: TemplatesFinder
    let projectDirectory: AbsolutePath

    package init(
        location: TemplateLocationType?,
        projectDirectory: AbsolutePath,
        homeDirectory: AbsolutePath,
        fileSystem: sending some FileSysteming
    ) async {
        self.location = location
        self.projectDirectory = projectDirectory
        self.finder = await TemplatesFinder(
            fileSystem: fileSystem,
            projectDirectory: projectDirectory,
            homeDirectory: homeDirectory
        )
    }

    package func run() async throws {
        if let location {
            let list = try await finder.list(for: location)

            table(for: list, in: location)
        } else {
            let list = try await finder.listAll()

            table(for: list.global, in: .global)
            table(for: list.project, in: .project(projectDirectory))
        }
    }

    private func table(for list: [Template], in location: TemplateLocationType) {
        Noora().info("Templates in \(location.dir)")

        Noora().table(
            headers: ["name", "description"],
            rows: list.reduce(into: [[String]]()) { partialResult, template in
                partialResult.append([template.config.name, template.path.pathString])
            }
        )
    }
}
