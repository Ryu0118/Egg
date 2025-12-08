import FileSystem
import Foundation
import Noora
import Path

package struct ListRunner {
    let location: TemplateLocationType?
    let finder: TemplatesFinder
    let projectDirectory: AbsolutePath
    let workingDirectory: AbsolutePath
    let hideDescription: Bool
    let noora: any Noorable

    package init(
        location: TemplateLocationType?,
        projectDirectory: AbsolutePath,
        workingDirectory: AbsolutePath,
        homeDirectory: AbsolutePath,
        fileSystem: some FileSysteming,
        hideDescription: Bool = false,
        noora: some Noorable = Noora()
    ) {
        self.location = location
        self.projectDirectory = projectDirectory
        self.workingDirectory = workingDirectory
        self.hideDescription = hideDescription
        self.noora = noora
        finder = TemplatesFinder(
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
            guard !(list.global.isEmpty && list.project.isEmpty) else {
                noora.info("No templates found.")
                return
            }

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

        noora.passthrough("Templates in \(location.dir)\n")

        if hideDescription {
            noora.table(
                headers: ["name"],
                rows: list.reduce(into: [[String]]()) { partialResult, template in
                    partialResult.append([template.config.name])
                }
            )
        } else {
            noora.table(
                headers: ["name", "description"],
                rows: list.reduce(into: [[String]]()) { partialResult, template in
                    partialResult.append([template.config.name, template.config.description])
                }
            )
        }
    }
}
