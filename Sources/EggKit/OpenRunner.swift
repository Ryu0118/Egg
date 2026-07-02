import FileManagerProtocol
import Foundation
import Interaction
import Noora
import ProcessRunning

#if canImport(System)
    import System
#else
    import SystemPackage
#endif

package struct OpenRunner {
    private let mode: OpenRunnerMode
    private let processRunner: any ProcessRunning
    private let templatesFinder: TemplatesFinder
    private let projectDirectory: URL
    private let workingDirectory: URL
    private let noora: any Noorable
    private let interaction: any InteractionProviding

    package init(
        mode: OpenRunnerMode,
        processRunner: any ProcessRunning,
        projectDirectory: URL,
        workingDirectory: URL,
        homeDirectory: URL,
        additionalSearchPaths: [URL] = [],
        fileManager: some FileManagerProtocol,
        noora: some Noorable = Noora(),
        interaction: some InteractionProviding = Terminal(),
    ) {
        self.mode = mode
        self.processRunner = processRunner
        self.projectDirectory = projectDirectory
        self.workingDirectory = workingDirectory
        self.noora = noora
        self.interaction = interaction
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
        case .interactive:
            try await runInteractiveMode()
        case let .direct(templateName, templatePath, location):
            try await openTemplateDirectory(
                templateName: templateName,
                templatePath: templatePath,
                location: location,
            )
        }
    }

    private func runInteractiveMode() async throws {
        let options = try await templatesFinder.listWithLocations()

        guard !options.isEmpty else {
            throw Error.noTemplatesFound
        }

        let selectedOption = noora.singleChoicePrompt(
            title: "Select Template to Open",
            question: "Which template would you like to open?",
            options: options,
            description: "Select a template to open in Finder.",
        )

        try await openTemplateDirectory(
            templateName: selectedOption.template.config.name,
            templatePath: selectedOption.template.path,
            location: selectedOption.location,
        )
    }

    private func openTemplateDirectory(
        templateName: String,
        templatePath: URL,
        location _: TemplateLocationType,
    ) async throws {
        do {
            _ = try await processRunner.run(
                .path("/usr/bin/open"),
                arguments: [templatePath.path],
            )

            interaction.writeSuccess("Opened template '\(templateName)' at \(templatePath.path)")
        } catch {
            throw Error.failedToOpen(
                templateName: templateName,
                path: templatePath,
                underlying: error,
            )
        }
    }

    enum Error: LocalizedError {
        case noTemplatesFound
        case failedToOpen(templateName: String, path: URL, underlying: Swift.Error)

        var errorDescription: String? {
            switch self {
            case .noTemplatesFound:
                "No templates found to open"
            case let .failedToOpen(templateName, path, underlying):
                "Failed to open template '\(templateName)' at \(path.path): \(underlying.localizedDescription)"
            }
        }
    }
}

package enum OpenRunnerMode: Codable {
    case interactive
    case direct(
        templateName: String,
        templatePath: URL,
        location: TemplateLocationType,
    )
}
