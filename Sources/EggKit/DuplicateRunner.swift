import Foundation
import FileSystem
import Path
import Noora
import Yams

package struct DuplicateRunner {
    private let mode: DuplicateRunnerMode
    private let templateLocation: TemplateLocation
    private let templatesFinder: TemplatesFinder
    private let projectDirectory: AbsolutePath
    private let workingDirectory: AbsolutePath
    private let fileSystem: any FileSysteming

    let decoder = YAMLDecoder()
    let encoder = YAMLEncoder.defaultEncoder()
    let validator = ConfigValidator()

    package init(
        mode: DuplicateRunnerMode,
        projectDirectory: AbsolutePath,
        workingDirectory: AbsolutePath,
        homeDirectory: AbsolutePath,
        fileSystem: some FileSysteming
    ) async {
        let templateLocation = TemplateLocation(
            homeDirectory: homeDirectory
        )
        self.mode = mode
        self.templateLocation = templateLocation
        self.projectDirectory = projectDirectory
        self.workingDirectory = workingDirectory
        self.fileSystem = fileSystem
        self.templatesFinder = TemplatesFinder(
            fileSystem: fileSystem,
            projectDirectory: projectDirectory,
            workingDirectory: workingDirectory,
            homeDirectory: homeDirectory
        )
    }

    package func run() async throws {
        switch mode {
        case .noora:
            try await runInteractiveMode()
        case .provided(_, let sourcePath, let sourceLocation, let newName, let newDescription):
            try await duplicateTemplate(
                sourcePath: try AbsolutePath(validating: sourcePath),
                sourceLocation: sourceLocation,
                newName: newName,
                newDescription: newDescription
            )
        }
    }

    private func runInteractiveMode() async throws {
        let noora = Noora()
        
        let options = try await prepareTemplateWithLocations()
        let selectedOption = selectSourceTemplate(options: options, noora: noora)
        let (newName, newDescription) = try await promptForNewTemplateInfo(
            sourceTemplate: selectedOption.template,
            sourceLocation: selectedOption.location,
            noora: noora
        )
        
        try await duplicateTemplate(
            sourcePath: selectedOption.template.path,
            sourceLocation: selectedOption.location,
            newName: newName,
            newDescription: newDescription
        )
    }

    private func prepareTemplateWithLocations() async throws -> [TemplateWithLocation] {
        let globalTemplates = try await templatesFinder.list(for: .global)
        let projectTemplates = try await templatesFinder.list(
            for: .project(
                projectDirectory,
                workingDirectory: workingDirectory
            )
        )

        let globalOptions = globalTemplates.map { TemplateWithLocation(template: $0, location: .global) }
        let projectOptions = projectTemplates.map {
            TemplateWithLocation(
                template: $0,
                location: .project(
                    projectDirectory,
                    workingDirectory: workingDirectory
                )
            )
        }

        let options = globalOptions + projectOptions

        guard !options.isEmpty else {
            throw Error.noTemplatesFound
        }

        return options
    }

    private func selectSourceTemplate(
        options: [TemplateWithLocation],
        noora: Noora
    ) -> TemplateWithLocation {
        noora.singleChoicePrompt(
            title: "Select Template to Duplicate",
            question: "Which template would you like to duplicate?",
            options: options,
            description: "Select a template to duplicate."
        )
    }

    private func promptForNewTemplateInfo(
        sourceTemplate: Template,
        sourceLocation: TemplateLocationType,
        noora: Noora
    ) async throws -> (name: String, description: String) {
        let defaultNewName = await generateDefaultName(
            baseName: sourceTemplate.config.name,
            sourceLocation: sourceLocation
        )
        let defaultNewDescription = sourceTemplate.config.description

        let newName = try await promptForNewName(
            defaultName: defaultNewName,
            noora: noora
        )
        
        let newDescription = promptForNewDescription(
            defaultDescription: defaultNewDescription,
            noora: noora
        )

        return (newName, newDescription)
    }

    private func promptForNewName(
        defaultName: String,
        noora: Noora
    ) async throws -> String {
        let newName = noora.textPrompt(
            title: "New Template Name",
            prompt: "Enter the name for the duplicated template (default: \(defaultName)):",
            collapseOnAnswer: true,
            validationRules: [
                NonEmptyValidationRule(error: "Template name cannot be empty."),
                DirectoryNameValidationRule(error: "Invalid directory name. Cannot contain '/' or start with whitespace."),
                LengthValidationRule.templateName
            ]
        )

        let finalNewName = if newName.isEmpty {
            defaultName
        } else {
            newName
        }

        guard !(try await templatesFinder.exists(finalNewName)) else {
            throw Error.targetAlreadyExists(name: finalNewName)
        }

        return finalNewName
    }

    private func promptForNewDescription(
        defaultDescription: String,
        noora: Noora
    ) -> String {
        let newDescription = noora.textPrompt(
            title: "New Template Description",
            prompt: "Enter the description for the duplicated template (default: \(defaultDescription)):",
            collapseOnAnswer: true,
            validationRules: [
                NonEmptyValidationRule(error: "Description cannot be empty."),
                LengthValidationRule.description
            ]
        )

        return if newDescription.isEmpty {
            defaultDescription
        } else {
            newDescription
        }
    }

    private func duplicateTemplate(
        sourcePath: AbsolutePath,
        sourceLocation: TemplateLocationType,
        newName: String,
        newDescription: String
    ) async throws {
        // Determine target location (same as source)
        let targetPath = templateLocation.template(newName, type: sourceLocation)

        // Ensure target directory doesn't exist
        guard !(try await fileSystem.exists(targetPath)) else {
            throw Error.targetAlreadyExists(name: newName)
        }

        // Copy entire template directory
        try await fileSystem.copy(sourcePath, to: targetPath)

        // Update config.yml with new name and description
        let configPath = targetPath.appending(component: "config.yml")
        try await updateConfig(
            at: configPath,
            newName: newName,
            newDescription: newDescription
        )

        Noora().success("Successfully duplicated template '\(newName)' at \(targetPath.pathString)")
    }


    private func updateConfig(
        at configPath: AbsolutePath,
        newName: String,
        newDescription: String
    ) async throws {
        // Read existing config
        let configData = try await fileSystem.readFile(at: configPath)
        var config = try decoder.decode(Config.self, from: configData)

        // Update name and description
        config = Config(
            name: newName,
            description: newDescription,
            version: config.version,
            macros: config.macros,
            preHatch: config.preHatch,
            hatch: config.hatch,
            postHatch: config.postHatch
        )

        // Validate updated config
        try await validator.validate(config)

        // Write updated config
        try await fileSystem.writeAsYAML(config, at: configPath, encoder: encoder, options: [.overwrite])
    }

    private func generateDefaultName(
        baseName: String,
        sourceLocation: TemplateLocationType
    ) async -> String {
        await DuplicateTemplateNameGenerator.generateDefaultName(
            baseName: baseName,
            sourceLocation: sourceLocation,
            templatesFinder: templatesFinder,
            emitValidationErrorLog: false
        )
    }

    enum Error: LocalizedError {
        case noTemplatesFound
        case targetAlreadyExists(name: String)
        case copyFailed(underlying: Swift.Error)

        var errorDescription: String? {
            switch self {
            case .noTemplatesFound:
                "No templates found to duplicate"
            case .targetAlreadyExists(let name):
                "A template with the name '\(name)' already exists at the target location"
            case .copyFailed(let underlying):
                "Failed to copy template: \(underlying.localizedDescription)"
            }
        }
    }
}

package enum DuplicateRunnerMode: Codable {
    case noora
    case provided(
        sourceName: String,
        sourcePath: String,
        sourceLocation: TemplateLocationType,
        newName: String,
        newDescription: String
    )
}
