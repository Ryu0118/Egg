import Foundation
import FileSystem
import Path
import Noora

package struct ListRunner {
    let location: TemplateLocationType?
    let finder: TemplatesFinder
    let projectDirectory: AbsolutePath
    let workingDirectory: AbsolutePath

    package init(
        location: TemplateLocationType?,
        projectDirectory: AbsolutePath,
        workingDirectory: AbsolutePath,
        homeDirectory: AbsolutePath,
        fileSystem: some FileSysteming
    ) {
        self.location = location
        self.projectDirectory = projectDirectory
        self.workingDirectory = workingDirectory
        self.finder = TemplatesFinder(
            fileSystem: fileSystem,
            projectDirectory: projectDirectory,
            workingDirectory: workingDirectory,
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
            table(
                for: list.project,
                in: .project(
                    projectDirectory,
                    workingDirectory: workingDirectory
                )
            )
        }
    }

    private func table(for list: [Template], in location: TemplateLocationType) {
        guard !list.isEmpty else {
            return
        }

        Noora().passthrough("Templates in \(location.dir)\n")

        Noora().table(
            headers: ["name", "description"],
            rows: list.reduce(into: [[String]]()) { partialResult, template in
                partialResult.append([template.config.name, template.config.description])
            }
        )
    }
}
