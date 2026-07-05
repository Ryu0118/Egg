import FileManagerProtocol
import Foundation
import Interaction

package struct ListRunner {
    private let mode: ListRunnerMode
    private let finder: TemplatesFinder
    private let projectDirectory: URL
    private let workingDirectory: URL
    private let additionalSearchPaths: [URL]
    private let hideDescription: Bool
    private let interaction: any InteractionProviding

    /// Initialize for display mode (backward compatible)
    package init(
        location: TemplateLocationType?,
        projectDirectory: URL,
        workingDirectory: URL,
        homeDirectory: URL,
        additionalSearchPaths: [URL] = [],
        fileManager: some FileManagerProtocol,
        hideDescription: Bool = false,
        interaction: some InteractionProviding = GuardedTerminal(),
    ) {
        mode = .display(location: location)
        self.projectDirectory = projectDirectory
        self.workingDirectory = workingDirectory
        self.additionalSearchPaths = additionalSearchPaths
        self.hideDescription = hideDescription
        self.interaction = interaction
        finder = TemplatesFinder(
            fileManager: fileManager,
            projectDirectory: projectDirectory,
            workingDirectory: workingDirectory,
            homeDirectory: homeDirectory,
            additionalSearchPaths: additionalSearchPaths,
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
        interaction: some InteractionProviding = GuardedTerminal(),
    ) {
        self.mode = mode
        self.projectDirectory = projectDirectory
        self.workingDirectory = workingDirectory
        self.additionalSearchPaths = additionalSearchPaths
        self.hideDescription = hideDescription
        self.interaction = interaction
        finder = TemplatesFinder(
            fileManager: fileManager,
            projectDirectory: projectDirectory,
            workingDirectory: workingDirectory,
            homeDirectory: homeDirectory,
            additionalSearchPaths: additionalSearchPaths,
        )
    }

    package func run() async throws {
        switch mode {
        case let .display(location):
            try await runDisplayMode(location: location)
        case let .mcp(location):
            // MCP mode returns result, use runMcp() instead
            _ = try await runMcp(location: location)
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
                    path: template.path.path(percentEncoded: false),
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
                    path: template.path.path(percentEncoded: false),
                ))
            }

            // Add project templates
            for template in list.project {
                templates.append(ListResult.TemplateInfo(
                    name: template.config.name,
                    description: template.config.description,
                    version: template.config.version,
                    location: "project",
                    path: template.path.path(percentEncoded: false),
                ))
            }

            // Add custom path templates
            for template in list.custom {
                templates.append(ListResult.TemplateInfo(
                    name: template.config.name,
                    description: template.config.description,
                    version: template.config.version,
                    location: "custom",
                    path: template.path.path(percentEncoded: false),
                ))
            }
        }

        return ListResult(templates: templates)
    }

    /// Run in display mode (shows tables using Interaction)
    private func runDisplayMode(location: TemplateLocationType?) async throws {
        if let location {
            let list = try await finder.list(for: location)
            table(for: list, in: location)
        } else {
            let list = try await finder.listAll()
            guard !(list.custom.isEmpty && list.global.isEmpty && list.project.isEmpty) else {
                interaction.writeInfo("No templates found.")
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
                    workingDirectory: workingDirectory,
                ),
            )
        }
    }

    private func table(for list: [Template], in location: TemplateLocationType) {
        guard !list.isEmpty else {
            return
        }

        interaction.writeLine("Templates in \(location.dir)")

        if hideDescription {
            interaction.writeTable(
                Table(
                    headers: ["name"],
                    rows: list.reduce(into: [[String]]()) { partialResult, template in
                        partialResult.append([template.config.name])
                    },
                ),
            )
        } else {
            interaction.writeTable(
                Table(
                    headers: ["name", "description"],
                    rows: list.reduce(into: [[String]]()) { partialResult, template in
                        partialResult.append([template.config.name, template.config.description])
                    },
                ),
            )
        }
    }
}
