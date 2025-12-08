import Foundation
import Path
import ProcessRunning
import Noora
import FileSystem

#if canImport(System)
import System
#else
import SystemPackage
#endif

package struct OpenRunner {
    private let mode: OpenRunnerMode
    private let processRunner: any ProcessRunning
    private let templatesFinder: TemplatesFinder
    private let projectDirectory: AbsolutePath
    private let workingDirectory: AbsolutePath
    private let noora: any Noorable

    package init(
        mode: OpenRunnerMode,
        processRunner: any ProcessRunning,
        projectDirectory: AbsolutePath,
        workingDirectory: AbsolutePath,
        homeDirectory: AbsolutePath,
        fileSystem: some FileSysteming,
        noora: some Noorable = Noora()
    ) {
        self.mode = mode
        self.processRunner = processRunner
        self.projectDirectory = projectDirectory
        self.workingDirectory = workingDirectory
        self.noora = noora
        self.templatesFinder = TemplatesFinder(
            fileSystem: fileSystem,
            projectDirectory: projectDirectory,
            workingDirectory: workingDirectory,
            homeDirectory: homeDirectory
        )
    }

    package func run() async throws {
        switch mode {
        case .interactive:
            try await runInteractiveMode()
        case .direct(let templateName, let templatePath, let location):
            try await openTemplateDirectory(
                templateName: templateName,
                templatePath: templatePath,
                location: location
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
            description: "Select a template to open in Finder."
        )

        try await openTemplateDirectory(
            templateName: selectedOption.template.config.name,
            templatePath: selectedOption.template.path,
            location: selectedOption.location
        )
    }

    private func openTemplateDirectory(
        templateName: String,
        templatePath: AbsolutePath,
        location: TemplateLocationType
    ) async throws {
        do {
            _ = try await processRunner.run(
                .path("/usr/bin/open"),
                arguments: [templatePath.pathString]
            )

            noora.success("Opened template '\(templateName)' at \(templatePath.pathString)")
        } catch {
            throw Error.failedToOpen(
                templateName: templateName,
                path: templatePath,
                underlying: error
            )
        }
    }

    enum Error: LocalizedError {
        case noTemplatesFound
        case failedToOpen(templateName: String, path: AbsolutePath, underlying: Swift.Error)

        var errorDescription: String? {
            switch self {
            case .noTemplatesFound:
                "No templates found to open"
            case .failedToOpen(let templateName, let path, let underlying):
                "Failed to open template '\(templateName)' at \(path.pathString): \(underlying.localizedDescription)"
            }
        }
    }
}

package enum OpenRunnerMode: Codable {
    case interactive
    case direct(
        templateName: String,
        templatePath: AbsolutePath,
        location: TemplateLocationType
    )
}
