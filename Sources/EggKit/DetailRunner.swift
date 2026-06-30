import FileManagerProtocol
import Foundation
import Noora

package struct DetailRunner {
    private let mode: DetailRunnerMode
    private let templatesFinder: TemplatesFinder
    private let projectDirectory: URL
    private let workingDirectory: URL
    private let noora: any Noorable
    private let displayer: TemplateDetailDisplayer

    package init(
        mode: DetailRunnerMode,
        projectDirectory: URL,
        workingDirectory: URL,
        homeDirectory: URL,
        additionalSearchPaths: [URL] = [],
        fileManager: some FileManagerProtocol,
        noora: some Noorable = Noora(),
    ) {
        self.mode = mode
        self.projectDirectory = projectDirectory
        self.workingDirectory = workingDirectory
        self.noora = noora
        displayer = TemplateDetailDisplayer(noora: noora)
        templatesFinder = TemplatesFinder(
            fileManager: fileManager,
            projectDirectory: projectDirectory,
            workingDirectory: workingDirectory,
            homeDirectory: homeDirectory,
            additionalSearchPaths: additionalSearchPaths,
        )
    }

    package func run() async throws {
        switch mode {
        case let .interactive(location):
            try await runInteractiveMode(location: location)
        case let .direct(template, location):
            displayer.display(template: template, location: location)
        case .mcp:
            // MCP mode returns result, use runMcp() instead
            break
        }
    }

    /// Run in MCP mode and return structured result
    package func runMcp(template: Template, location: TemplateLocationType) -> DetailResult {
        let formatter = TemplateDetailFormatter()
        let formatted = formatter.format(template: template, location: location)

        let macros = formatted.macros.map { macro in
            DetailResult.MacroInfo(
                name: macro.name,
                flag: macro.flag,
                type: macro.type,
                description: macro.description,
                defaultValue: macro.defaultValue,
                choices: macro.choices,
                validation: macro.validation,
            )
        }

        let exampleMcpMacros = (template.config.macros ?? []).reduce(into: [String: String]()) { result, macro in
            result[macro.name] = formatter.generateExampleValue(for: macro)
        }

        return DetailResult(
            basicInfo: DetailResult.BasicInfo(
                name: formatted.basicInfo.name,
                description: formatted.basicInfo.description,
                version: formatted.basicInfo.version,
                locationName: formatted.basicInfo.locationName,
                locationDir: formatted.basicInfo.locationDir,
                path: formatted.basicInfo.path,
            ),
            macros: macros,
            exampleCliCommand: formatted.exampleCommand,
            exampleMcpArguments: DetailResult.ExampleMcpArguments(
                templateName: template.config.name,
                macros: exampleMcpMacros,
            ),
            agentUsage: DetailResult.AgentUsage(
                recommendedFlow: [
                    "Read required macros via the egg_template_detail MCP tool (or 'egg template detail <name>').",
                    "Create a transaction without applying changes: egg_hatch_preview MCP tool, or 'egg hatch preview <name> --macro value'.",
                    "Inspect the returned changes and warnings.",
                    "Only after approval, apply with the applyToken: egg_hatch_apply, or 'egg hatch apply <applyToken>'.",
                    "If the applied scaffold must be undone, use the rollbackId: egg_hatch_rollback, or 'egg hatch rollback <rollbackId>'.",
                ],
                previewCliCommand: formatted.exampleCommand.replacingOccurrences(
                    of: "egg hatch",
                    with: "egg hatch preview",
                ),
                previewMcpTool: "egg_hatch_preview",
                applyMcpTool: "egg_hatch_apply",
                rollbackMcpTool: "egg_hatch_rollback",
                macroKeyFormat: "Use exact config macro names as keys, e.g. ___MODULE_NAME___. Do not convert MCP macro keys to CLI flags.",
            ),
        )
    }

    private func runInteractiveMode(location: TemplateLocationType?) async throws {
        let options: [TemplateWithLocation]

        if let location {
            let templates = try await templatesFinder.list(for: location)
            options = templates.map { TemplateWithLocation(template: $0, location: location) }
        } else {
            options = try await templatesFinder.listWithLocations()
        }

        guard !options.isEmpty else {
            throw Error.noTemplatesFound
        }

        let selectedOption = noora.singleChoicePrompt(
            title: "Select Template",
            question: "Which template would you like to view?",
            options: options,
            description: "Select a template to view its details.",
        )

        displayer.display(
            template: selectedOption.template,
            location: selectedOption.location,
        )
    }

    enum Error: LocalizedError {
        case noTemplatesFound

        var errorDescription: String? {
            switch self {
            case .noTemplatesFound:
                "No templates found"
            }
        }
    }
}
