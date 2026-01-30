import FileManagerProtocol
import Foundation
import Noora

package struct ListRunner {
    private let mode: ListRunnerMode
    private let finder: TemplatesFinder
    private let projectDirectory: URL
    private let workingDirectory: URL
    private let additionalSearchPaths: [URL]
    private let hideDescription: Bool
    private let noora: any Noorable

    /// Initialize for display mode (backward compatible)
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
        self.mode = .display
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

    /// Initialize with explicit mode
    package init(
        mode: ListRunnerMode,
        projectDirectory: URL,
        workingDirectory: URL,
        homeDirectory: URL,
        additionalSearchPaths: [URL] = [],
        fileManager: some FileManagerProtocol,
        hideDescription: Bool = false,
        noora: some Noorable = Noora()
    ) {
        self.mode = mode
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
        switch mode {
        case .display:
            try await runDisplayMode(location: nil)
        case let .mcp(location):
            // MCP mode returns result, use runMcp() instead
            _ = try await runMcp(location: location)
        }
    }

    /// Run in display mode (shows tables using Noora)
    private func runDisplayMode(location: TemplateLocationType?) async throws {
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

    /// Run in MCP mode and return structured result
    package func runMcp(location: TemplateLocationType? = nil) async throws -> ListResult {
        var templates: [ListResult.TemplateInfo] = []

        if let location {
            let list = try await finder.list(for: location)
            templates = list.map { template in
                ListResult.TemplateInfo(
                    name: template.config.name,
                    description: template.config.description,
                    version: template.config.version,
                    location: location.name,
                    path: template.path.path(percentEncoded: false)
                )
            }
        } else {
            let list = try await finder.listAll()

            // Add global templates
            for template in list.global {
                templates.append(ListResult.TemplateInfo(
                    name: template.config.name,
                    description: template.config.description,
                    version: template.config.version,
                    location: "global",
                    path: template.path.path(percentEncoded: false)
                ))
            }

            // Add project templates
            for template in list.project {
                templates.append(ListResult.TemplateInfo(
                    name: template.config.name,
                    description: template.config.description,
                    version: template.config.version,
                    location: "project",
                    path: template.path.path(percentEncoded: false)
                ))
            }

            // Add custom path templates
            for template in list.custom {
                templates.append(ListResult.TemplateInfo(
                    name: template.config.name,
                    description: template.config.description,
                    version: template.config.version,
                    location: "custom",
                    path: template.path.path(percentEncoded: false)
                ))
            }
        }

        return ListResult(templates: templates)
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
