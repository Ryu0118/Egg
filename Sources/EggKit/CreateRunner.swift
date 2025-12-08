import Foundation
import FileSystem
import Path
import Noora

package struct CreateRunner {
    private let mode: CreateRunnerMode
    private let templateLocation: TemplateLocation
    private let templateCreator: TemplateCreator
    private let templatesFinder: TemplatesFinder
    private let projectDirectory: AbsolutePath
    private let workingDirectory: AbsolutePath
    private let noora: any Noorable

    package init(
        mode: CreateRunnerMode,
        skipConfig: Bool,
        projectDirectory: AbsolutePath,
        workingDirectory: AbsolutePath,
        homeDirectory: AbsolutePath,
        fileSystem: some FileSysteming,
        noora: some Noorable = Noora()
    ) async {
        let templateLocation = TemplateLocation(
            homeDirectory: homeDirectory
        )
        self.mode = mode
        self.templateLocation = templateLocation
        self.projectDirectory = projectDirectory
        self.workingDirectory = workingDirectory
        self.noora = noora
        self.templateCreator = TemplateCreator(
            skipConfig: skipConfig,
            templateLocating: templateLocation,
            fileSystem: fileSystem,
        )
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
            let templateName = noora.textPrompt(
                title: "Template name",
                prompt: "How would you like to name your template?",
                collapseOnAnswer: true,
                validationRules: [
                    NonEmptyValidationRule(error: "Project name cannot be empty."),
                    DirectoryNameValidationRule(error: "Invalid directory name. Cannot contain '/' or start with whitespace."),
                    LengthValidationRule.templateName
                ]
            )

            guard !(try await templatesFinder.exists(templateName)) else {
                throw Error.templateAlreadyExists
            }

            let description = noora.textPrompt(
                title: "Template description",
                prompt: "Please enter a description for your template.",
                collapseOnAnswer: true,
                validationRules: [
                    NonEmptyValidationRule(error: "Description cannot be empty."),
                    LengthValidationRule.description
                ]
            )

            let locationType: TemplateLocationType = noora.singleChoicePrompt(
                title: "Template Location",
                question: "Where would you like to store your template?",
                options: [
                    .global,
                    .project(
                        projectDirectory,
                        workingDirectory: workingDirectory
                    )
                ],
                description: "Global templates are available across all projects, while project templates are specific to the current project."
            )

            try await templateCreator.create(
                templateName,
                description: description,
                in: locationType
            )

            let templateDir = templateLocation.template(templateName, type: locationType)
            successLog(name: templateName, templateDir: templateDir)

        case .direct(let name, let description, let location):
            let locationConcreteType = location.toConcreteType(projectDirectory, workingDirectory: workingDirectory)
            try await templateCreator.create(
                name,
                description: description,
                in: locationConcreteType
            )

            let templateDir = templateLocation.template(name, type: locationConcreteType)
            successLog(name: name, templateDir: templateDir)
        }
    }

    private func successLog(name: String, templateDir: AbsolutePath) {
        noora.success("Successfully created template '\(name)' at \(templateDir.pathString)")
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
    case interactive
    case direct(name: String, description: String, location: TemplateLocationType.Kind)
}
