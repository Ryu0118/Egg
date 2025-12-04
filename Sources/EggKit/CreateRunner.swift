import Foundation
import FileSystem
import Path
import Noora

package struct CreateRunner {
    private let mode: CreateRunnerMode
    private let templateLocation: TemplateLocation
    private let templateCreator: TemplateCreator
    private let templatesFinder: TemplatesFinder

    package init(
        mode: CreateRunnerMode,
        skipConfig: Bool,
        projectDirectory: AbsolutePath,
        homeDirectory: AbsolutePath,
        fileSystem: some FileSysteming
    ) {
        let templateLocation = TemplateLocation(
            projectDirectory: projectDirectory,
            homeDirectory: homeDirectory
        )
        self.mode = mode
        self.templateLocation = templateLocation
        self.templateCreator = TemplateCreator(
            skipConfig: skipConfig,
            templateLocating: templateLocation,
            fileSystem: fileSystem,
        )
        self.templatesFinder = TemplatesFinder(
            fileSystem: fileSystem,
            projectDirectory: projectDirectory,
            homeDirectory: homeDirectory
        )
    }

    package func run() async throws {
        switch mode {
        case .noora:
            let templateName = Noora().textPrompt(
                title: "Template name",
                prompt: "How would you like to name your template?",
                collapseOnAnswer: true,
                validationRules: [
                    NonEmptyValidationRule(error: "Project name cannot be empty."),
                    DirectoryNameValidationRule(error: "Invalid directory name. Cannot contain '/' or start with whitespace.")
                ]
            )

            guard !(try await templatesFinder.exists(templateName)) else {
                throw Error.templateAlreadyExists
            }

            let locationType: TemplateLocationType = Noora().singleChoicePrompt(
                title: "Template Location",
                question: "Where would you like to store your template?",
                description: "Global templates are available across all projects, while project templates are specific to the current project."
            )

            try await templateCreator.create(templateName, in: locationType)

            let templateDir = templateLocation.template(templateName, type: locationType)
            successLog(name: templateName, templateDir: templateDir)

        case .provided(let name, let location):
            try await templateCreator.create(name, in: location)

            let templateDir = templateLocation.template(name, type: location)
            successLog(name: name, templateDir: templateDir)
        }
    }

    private func successLog(name: String, templateDir: AbsolutePath) {
        Noora().success("Successfully created template '\(name)' at \(templateDir.pathString)")
    }

    enum Error: LocalizedError {
        case templateAlreadyExists

        var errorDescription: String? {
            switch self {
            case .templateAlreadyExists:
                "A template with the same name already exists"
            }
        }
    }
}

package enum CreateRunnerMode: Codable {
    case noora
    case provided(name: String, location: TemplateLocationType)
}
