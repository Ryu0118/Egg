import FileManagerProtocol
import Foundation
import Noora

package struct CreateRunner {
    private let mode: CreateRunnerMode
    private let templateLocation: TemplateLocation
    private let templateCreator: TemplateCreator
    private let templatesFinder: TemplatesFinder
    private let projectDirectory: URL
    private let workingDirectory: URL
    private let noora: any Noorable

    package init(
        mode: CreateRunnerMode,
        skipConfig: Bool,
        projectDirectory: URL,
        workingDirectory: URL,
        homeDirectory: URL,
        fileManager: some FileManagerProtocol,
        noora: some Noorable = Noora()
    ) {
        let templateLocation = TemplateLocation(
            homeDirectory: homeDirectory
        )
        self.mode = mode
        self.templateLocation = templateLocation
        self.projectDirectory = projectDirectory
        self.workingDirectory = workingDirectory
        self.noora = noora
        templateCreator = TemplateCreator(
            skipConfig: skipConfig,
            templateLocating: templateLocation,
            fileManager: fileManager
        )
        templatesFinder = TemplatesFinder(
            fileManager: fileManager,
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
                    LengthValidationRule.templateName,
                ]
            )

            guard !templatesFinder.exists(templateName) else {
                throw Error.templateAlreadyExists
            }

            let description = noora.textPrompt(
                title: "Template description",
                prompt: "Please enter a description for your template.",
                collapseOnAnswer: true,
                validationRules: [
                    NonEmptyValidationRule(error: "Description cannot be empty."),
                    LengthValidationRule.description,
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
                    ),
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

        case let .direct(name, description, location):
            let locationConcreteType = location.toConcreteType(projectDirectory, workingDirectory: workingDirectory)
            try await templateCreator.create(
                name,
                description: description,
                in: locationConcreteType
            )

            let templateDir = templateLocation.template(name, type: locationConcreteType)
            successLog(name: name, templateDir: templateDir)

        case .mcp:
            // MCP mode returns result, use runMcp() instead
            break
        }
    }

    /// Run in MCP mode and return structured result
    package func runMcp(
        name: String,
        description: String,
        location: TemplateLocationType.Kind
    ) async throws -> CreateResult {
        let locationConcreteType = location.toConcreteType(projectDirectory, workingDirectory: workingDirectory)

        guard !templatesFinder.exists(name) else {
            throw Error.templateAlreadyExists
        }

        try await templateCreator.create(
            name,
            description: description,
            in: locationConcreteType
        )

        let templateDir = templateLocation.template(name, type: locationConcreteType)

        return CreateResult(
            name: name,
            description: description,
            location: location.rawValue,
            path: templateDir.path(percentEncoded: false)
        )
    }

    private func successLog(name: String, templateDir: URL) {
        noora.success("Successfully created template '\(name)' at \(templateDir.path)")
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
    case mcp(name: String, description: String, location: TemplateLocationType.Kind)
}
