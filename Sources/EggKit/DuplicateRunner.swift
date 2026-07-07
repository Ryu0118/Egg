import FileManagerProtocol
import Foundation
import Interaction
import Yams

package struct DuplicateRunner {
    private let mode: DuplicateRunnerMode
    private let templateLocation: TemplateLocation
    private let templatesFinder: TemplatesFinder
    private let projectDirectory: URL
    private let workingDirectory: URL
    private let fileManager: any FileManagerProtocol
    private let interaction: any InteractionProviding

    let decoder = YAMLDecoder()
    let encoder = YAMLEncoder.defaultEncoder()
    let validator = ConfigValidator()

    package init(
        mode: DuplicateRunnerMode,
        projectDirectory: URL,
        workingDirectory: URL,
        homeDirectory: URL,
        additionalSearchPaths: [URL] = [],
        fileManager: some FileManagerProtocol,
        interaction: some InteractionProviding = GuardedTerminal(),
    ) {
        let templateLocation = TemplateLocation(
            homeDirectory: homeDirectory,
        )
        self.mode = mode
        self.templateLocation = templateLocation
        self.projectDirectory = projectDirectory
        self.workingDirectory = workingDirectory
        self.fileManager = fileManager
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
        case let .direct(_, sourcePath, sourceLocation, newName, newDescription):
            try await duplicateTemplate(
                sourcePath: URL(filePath: sourcePath),
                sourceLocation: sourceLocation,
                newName: newName,
                newDescription: newDescription,
            )
        case .mcp:
            // MCP mode returns result, use runMcp() instead
            break
        }
    }

    /// Run in MCP mode and return structured result
    package func runMcp(
        sourceName: String,
        sourcePath: String,
        sourceLocation: TemplateLocationType,
        newName: String,
        newDescription: String,
    ) async throws -> DuplicateResult {
        // newName becomes a path component (templateLocation.template below).
        // Unlike the CLI/interactive path, MCP callers never go through
        // Interaction's interactive validation prompt, so this must be checked
        // explicitly and BEFORE any filesystem mutation — otherwise a
        // traversal name (e.g. '../../../etc/evil') would copy the whole
        // source template tree to an arbitrary path before the config-name
        // validation below ever runs.
        guard await ValidationRule.directoryName(error: "")(newName) == nil else {
            throw Error.invalidNewName(name: newName)
        }

        let sourcePathURL = URL(filePath: sourcePath)

        // Determine target location (same as source)
        let targetPath = templateLocation.template(newName, type: sourceLocation)

        // Ensure target directory doesn't exist. existsAsLink, not fileExists:
        // a dangling symlink sitting exactly at the target name must still be
        // treated as "occupied," not silently copied over.
        guard !fileManager.existsAsLink(targetPath) else {
            throw Error.targetAlreadyExists(name: newName)
        }

        // Copy entire template directory, then update its config. If anything
        // after the copy fails (e.g. config validation), roll back the copy —
        // a failed duplicate must not leave a partial template behind.
        try fileManager.copyItem(at: sourcePathURL, to: targetPath)
        do {
            let configPath = targetPath.appendingPathComponent("config.yml")
            try await updateConfig(
                at: configPath,
                newName: newName,
                newDescription: newDescription,
            )
        } catch {
            try? fileManager.removeItem(at: targetPath)
            throw error
        }

        return DuplicateResult(
            sourceName: sourceName,
            newName: newName,
            newDescription: newDescription,
            location: sourceLocation.name,
            path: targetPath.path(percentEncoded: false),
        )
    }

    private func runInteractiveMode() async throws {
        let options = try await prepareTemplateWithLocations()
        let selectedOption = selectSourceTemplate(options: options)
        let (newName, newDescription) = try await promptForNewTemplateInfo(
            sourceTemplate: selectedOption.template,
            sourceLocation: selectedOption.location,
        )

        try await duplicateTemplate(
            sourcePath: selectedOption.template.path,
            sourceLocation: selectedOption.location,
            newName: newName,
            newDescription: newDescription,
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
        options: [TemplateWithLocation],
    ) -> TemplateWithLocation {
        interaction.singleChoicePrompt(
            title: "Select Template to Duplicate",
            question: "Which template would you like to duplicate?",
            options: options,
            description: "Select a template to duplicate.",
        )
    }

    private func promptForNewTemplateInfo(
        sourceTemplate: Template,
        sourceLocation: TemplateLocationType,
    ) async throws -> (name: String, description: String) {
        let defaultNewName = await generateDefaultName(
            baseName: sourceTemplate.config.name,
            sourceLocation: sourceLocation,
        )
        let defaultNewDescription = sourceTemplate.config.description

        let newName = try await promptForNewName(
            defaultName: defaultNewName,
        )

        let newDescription = await promptForNewDescription(
            defaultDescription: defaultNewDescription,
        )

        return (newName, newDescription)
    }

    private func promptForNewName(
        defaultName: String,
    ) async throws -> String {
        let newName = await interaction.textPrompt(
            title: "New Template Name",
            prompt: "Enter the name for the duplicated template (default: \(defaultName)):",
            collapsesOnAnswer: true,
            validationRules: [
                .nonEmpty(message: "Template name cannot be empty."),
                .directoryName(error: "Invalid directory name. Cannot contain '/' or start with whitespace."),
                .templateNameLength,
            ],
        )

        let finalNewName = if newName.isEmpty {
            defaultName
        } else {
            newName
        }

        guard await !templatesFinder.exists(finalNewName) else {
            throw Error.targetAlreadyExists(name: finalNewName)
        }

        return finalNewName
    }

    private func promptForNewDescription(
        defaultDescription: String,
    ) async -> String {
        let newDescription = await interaction.textPrompt(
            title: "New Template Description",
            prompt: "Enter the description for the duplicated template (default: \(defaultDescription)):",
            collapsesOnAnswer: true,
            validationRules: [
                .nonEmpty(message: "Description cannot be empty."),
                .descriptionLength,
            ],
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
        newDescription: String,
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
            newDescription: newDescription,
        )

        interaction.writeSuccess("Successfully duplicated template '\(newName)' at \(targetPath.path(percentEncoded: false))")
    }

    private func updateConfig(
        at configPath: URL,
        newName: String,
        newDescription: String,
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
            postHatch: config.postHatch,
        )

        // Validate updated config
        try await validator.validate(config)

        // Write updated config
        try fileManager.writeAsYAML(config, at: configPath, encoder: encoder)
    }

    private func generateDefaultName(
        baseName: String,
        sourceLocation: TemplateLocationType,
    ) async -> String {
        await DuplicateTemplateNameGenerator.generateDefaultName(
            baseName: baseName,
            sourceLocation: sourceLocation,
            templatesFinder: templatesFinder,
            emitValidationErrorLog: false,
        )
    }

    enum Error: LocalizedError {
        case noTemplatesFound
        case targetAlreadyExists(name: String)
        case copyFailed(underlying: Swift.Error)
        case invalidNewName(name: String)

        var errorDescription: String? {
            switch self {
            case .noTemplatesFound:
                "No templates found to duplicate"
            case let .targetAlreadyExists(name):
                "A template with the name '\(name)' already exists at the target location"
            case let .copyFailed(underlying):
                "Failed to copy template: \(underlying.localizedDescription)"
            case let .invalidNewName(name):
                "Invalid directory name '\(name)'. Cannot contain '/' or start with whitespace."
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
        newDescription: String,
    )
    case mcp(
        sourceName: String,
        sourcePath: String,
        sourceLocation: TemplateLocationType,
        newName: String,
        newDescription: String,
    )
}
