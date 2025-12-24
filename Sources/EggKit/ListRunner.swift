import FileManagerProtocol
import Foundation
import Noora

package struct ListRunner {
    let location: TemplateLocationType?
    let finder: TemplatesFinder
    let projectDirectory: URL
    let workingDirectory: URL
    let additionalSearchPaths: [URL]
    let hideDescription: Bool
    let noora: any Noorable

    package init(
        location: TemplateLocationType?,
        projectDirectory: URL,
        workingDirectory: URL,
        homeDirectory: URL,
        additionalSearchPaths: [URL] = [],
        fileManager: some FileManagerProtocol,
        hideDescription: Bool = false,
        noora: some Noorable = Noora()
    ) {
        self.location = location
        self.projectDirectory = projectDirectory
        self.workingDirectory = workingDirectory
        self.additionalSearchPaths = additionalSearchPaths
        self.hideDescription = hideDescription
        self.noora = noora
        finder = TemplatesFinder(
            fileManager: fileManager,
            projectDirectory: projectDirectory,
            workingDirectory: workingDirectory,
            homeDirectory: homeDirectory,
            additionalSearchPaths: additionalSearchPaths
        )
    }

    package func run() async throws {
        if let location {
            let list = try await finder.list(for: location)

            table(for: list, in: location)
        } else {
            let list = try await finder.listAll()
            guard !(list.custom.isEmpty && list.global.isEmpty && list.project.isEmpty) else {
                noora.info("No templates found.")
                return
            }

            // Display custom path templates first
            for customPath in additionalSearchPaths {
                let customTemplates = list.custom.filter { template in
                    template.path.path(percentEncoded: false).hasPrefix(customPath.path(percentEncoded: false))
                }
                if !customTemplates.isEmpty {
                    table(for: customTemplates, in: .custom(customPath))
                }
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
