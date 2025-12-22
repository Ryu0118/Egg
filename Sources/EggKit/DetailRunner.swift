import FileManagerProtocol
import Foundation
import Noora

package struct DetailRunner {
    private let mode: DetailRunnerMode
    private let templatesFinder: TemplatesFinder
    private let projectDirectory: URL
    private let workingDirectory: URL
    private let noora: any Noorable

    package init(
        mode: DetailRunnerMode,
        projectDirectory: URL,
        workingDirectory: URL,
        homeDirectory: URL,
        fileManager: some FileManagerProtocol,
        noora: some Noorable = Noora()
    ) {
        self.mode = mode
        self.projectDirectory = projectDirectory
        self.workingDirectory = workingDirectory
        self.noora = noora
        templatesFinder = TemplatesFinder(
            fileManager: fileManager,
            projectDirectory: projectDirectory,
            workingDirectory: workingDirectory,
            homeDirectory: homeDirectory
        )
    }

    package func run() async throws {
        switch mode {
        case let .interactive(location):
            try await runInteractiveMode(location: location)
        case let .direct(template, location):
            displayTemplateDetail(template: template, location: location)
        }
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
            description: "Select a template to view its details."
        )

        displayTemplateDetail(
            template: selectedOption.template,
            location: selectedOption.location
        )
    }

    private func displayTemplateDetail(template: Template, location: TemplateLocationType) {
        let formatter = TemplateDetailFormatter()
        let detail = formatter.format(template: template, location: location)

        let separator = String(repeating: "─", count: 60)

        // Header
        noora.passthrough("\n\(separator)\n", tab: 0)
        noora.passthrough("\(detail.basicInfo.name)\n", tab: 1)
        noora.passthrough("\(separator)\n\n", tab: 0)

        // Basic Info Section
        noora.passthrough("Description:  \(detail.basicInfo.description)\n", tab: 1)
        if let version = detail.basicInfo.version {
            noora.passthrough("Version:      \(version)\n", tab: 1)
        }
        noora.passthrough("Location:     \(detail.basicInfo.locationName) (\(detail.basicInfo.locationDir))\n", tab: 1)
        noora.passthrough("Path:         \(detail.basicInfo.path)\n\n", tab: 1)

        // Macros Section
        if detail.macros.isEmpty {
            noora.passthrough("Macros: None\n\n", tab: 1)
        } else {
            noora.passthrough("\(separator)\n", tab: 0)
            noora.passthrough("Macros (\(detail.macros.count))\n", tab: 1)
            noora.passthrough("\(separator)\n\n", tab: 0)

            for (index, macro) in detail.macros.enumerated() {
                displayMacroDetail(macro: macro, index: index + 1)
            }
        }

        // Example Command Section
        noora.passthrough("\(separator)\n", tab: 0)
        noora.passthrough("Example Command\n", tab: 1)
        noora.passthrough("\(separator)\n\n", tab: 0)
        noora.passthrough("\(detail.exampleCommand)\n\n", tab: 1)
    }

    private func displayMacroDetail(macro: TemplateDetailFormatter.FormattedMacro, index: Int) {
        noora.passthrough("\(index). \(macro.flag)\n", tab: 1)
        noora.passthrough("Name:        \(macro.name)\n", tab: 2)
        noora.passthrough("Type:        \(macro.type)\n", tab: 2)
        noora.passthrough("Description: \(macro.description)\n", tab: 2)

        if let defaultValue = macro.defaultValue {
            noora.passthrough("Default:     \(defaultValue)\n", tab: 2)
        }

        if let choices = macro.choices, !choices.isEmpty {
            noora.passthrough("Choices:\n", tab: 2)
            for choice in choices {
                noora.passthrough("- \(choice)\n", tab: 3)
            }
        }

        if let validation = macro.validation {
            noora.passthrough("Validation:  \(validation)\n", tab: 2)
        }

        noora.passthrough("\n", tab: 0)
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
