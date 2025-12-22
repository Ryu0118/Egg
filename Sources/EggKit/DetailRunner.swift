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
        fileManager: some FileManagerProtocol,
        noora: some Noorable = Noora()
    ) {
        self.mode = mode
        self.projectDirectory = projectDirectory
        self.workingDirectory = workingDirectory
        self.noora = noora
        self.displayer = TemplateDetailDisplayer(noora: noora)
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
            displayer.display(template: template, location: location)
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

        displayer.display(
            template: selectedOption.template,
            location: selectedOption.location
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
