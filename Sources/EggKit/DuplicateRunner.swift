import FileManagerProtocol
import Foundation
import Noora
import Yams

package struct DuplicateRunner {
    private let mode: DuplicateRunnerMode
    private let templateLocation: TemplateLocation
    private let templatesFinder: TemplatesFinder
    private let projectDirectory: URL
    private let workingDirectory: URL
    private let fileManager: any FileManagerProtocol
    private let noora: any Noorable

    let decoder = YAMLDecoder()
    let encoder = YAMLEncoder.defaultEncoder()
    let validator = ConfigValidator()

    package init(
        mode: DuplicateRunnerMode,
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
        self.fileManager = fileManager
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
        case .interactive:
            try await runInteractiveMode()
        case let .direct(_, sourcePath, sourceLocation, newName, newDescription):
            try await duplicateTemplate(
                sourcePath: URL(filePath: sourcePath),
                sourceLocation: sourceLocation,
                newName: newName,
                newDescription: newDescription
            )
        }
    }

    private func runInteractiveMode() async throws {
        let options = try await prepareTemplateWithLocations()
        let selectedOption = selectSourceTemplate(options: options)
        let (newName, newDescription) = try await promptForNewTemplateInfo(
            sourceTemplate: selectedOption.template,
            sourceLocation: selectedOption.location
        )

        try await duplicateTemplate(
            sourcePath: selectedOption.template.path,
            sourceLocation: selectedOption.location,
            newName: newName,
            newDescription: newDescription
        )
    }

    private func prepareTemplateWithLocations() async throws -> [TemplateWithLocation] {
        let options = try await templatesFinder.listWithLocations()

        guard !options.isEmpty else {
            throw Error.noTemplatesFound
        }

        return options
    }

    private func selectSourceTemplate(
        options: [TemplateWithLocation]
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
        sourceLocation: TemplateLocationType
    ) async throws -> (name: String, description: String) {
        let defaultNewName = await generateDefaultName(
            baseName: sourceTemplate.config.name,
            sourceLocation: sourceLocation
        )
        let defaultNewDescription = sourceTemplate.config.description

        let newName = try await promptForNewName(
            defaultName: defaultNewName
        )

        let newDescription = promptForNewDescription(
            defaultDescription: defaultNewDescription
        )

        return (newName, newDescription)
    }

    private func promptForNewName(
        defaultName: String
    ) async throws -> String {
        let newName = noora.textPrompt(
            title: "New Template Name",
            prompt: "Enter the name for the duplicated template (default: \(defaultName)):",
            collapseOnAnswer: true,
            validationRules: [
                NonEmptyValidationRule(error: "Template name cannot be empty."),
                DirectoryNameValidationRule(error: "Invalid directory name. Cannot contain '/' or start with whitespace."),
                LengthValidationRule.templateName,
            ]
        )

        let finalNewName = if newName.isEmpty {
            defaultName
        } else {
            newName
        }

        guard !templatesFinder.exists(finalNewName) else {
            throw Error.targetAlreadyExists(name: finalNewName)
        }

        return finalNewName
    }

    private func promptForNewDescription(
        defaultDescription: String
    ) -> String {
        let newDescription = noora.textPrompt(
            title: "New Template Description",
            prompt: "Enter the description for the duplicated template (default: \(defaultDescription)):",
            collapseOnAnswer: true,
            validationRules: [
                NonEmptyValidationRule(error: "Description cannot be empty."),
                LengthValidationRule.description,
            ]
        )

        return if newDescription.isEmpty {
            defaultDescription
        } else {
            newDescription
        }
    }

    private func duplicateTemplate(
        sourcePath: URL,
        sourceLocation: TemplateLocationType,
        newName: String,
        newDescription: String
    ) async throws {
        // Determine target location (same as source)
        let targetPath = templateLocation.template(newName, type: sourceLocation)

        // Ensure target directory doesn't exist
        guard !fileManager.fileExists(atPath: targetPath.path(percentEncoded: false)) else {
            throw Error.targetAlreadyExists(name: newName)
        }

        // Copy entire template directory
        try fileManager.copyItem(at: sourcePath, to: targetPath)

        // Update config.yml with new name and description
        let configPath = targetPath.appendingPathComponent("config.yml")
        try await updateConfig(
            at: configPath,
            newName: newName,
            newDescription: newDescription
        )

        noora.success("Successfully duplicated template '\(newName)' at \(targetPath.path(percentEncoded: false))")
    }

    private func updateConfig(
        at configPath: URL,
        newName: String,
        newDescription: String
    ) async throws {
        // Read existing config
        let configData = try fileManager.readFile(at: configPath)
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
        try fileManager.writeAsYAML(config, at: configPath, encoder: encoder)
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
            case let .targetAlreadyExists(name):
                "A template with the name '\(name)' already exists at the target location"
            case let .copyFailed(underlying):
                "Failed to copy template: \(underlying.localizedDescription)"
            }
        }
    }
}

package enum DuplicateRunnerMode: Codable {
    case interactive
    case direct(
        sourceName: String,
        sourcePath: String,
        sourceLocation: TemplateLocationType,
        newName: String,
        newDescription: String
    )
}
