import FileManagerProtocol
import Foundation
import Noora

package struct MoveRunner {
    private let mode: MoveRunnerMode
    private let force: Bool
    private let templateLocation: TemplateLocation
    private let templatesFinder: TemplatesFinder
    private let projectDirectory: URL
    private let workingDirectory: URL
    private let fileManager: any FileManagerProtocol
    private let noora: any Noorable

    package init(
        mode: MoveRunnerMode,
        force: Bool,
        projectDirectory: URL,
        workingDirectory: URL,
        homeDirectory: URL,
        additionalSearchPaths: [URL] = [],
        fileManager: some FileManagerProtocol,
        noora: some Noorable = Noora(),
    ) {
        let templateLocation = TemplateLocation(
            homeDirectory: homeDirectory,
        )
        self.mode = mode
        self.force = force
        self.templateLocation = templateLocation
        self.projectDirectory = projectDirectory
        self.workingDirectory = workingDirectory
        self.fileManager = fileManager
        self.noora = noora
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
        case let .selectTarget(name, pathString, sourceLocation):
            try await runSelectTargetMode(
                name: name,
                path: URL(filePath: pathString),
                sourceLocation: sourceLocation,
            )
        case let .direct(name, pathString, sourceLocation, targetLocation):
            try await moveTemplate(
                name: name,
                sourcePath: URL(filePath: pathString),
                sourceLocation: sourceLocation,
                targetLocation: targetLocation,
            )
        case .mcp:
            // MCP mode returns result, use runMcp() instead
            break
        }
    }

    /// Run in MCP mode and return structured result
    /// Note: MCP mode always uses force=true (overwrites existing)
    package func runMcp(
        name: String,
        path: String,
        sourceLocation: TemplateLocationType,
        targetLocation: TemplateLocationType,
    ) async throws -> MoveResult {
        let sourcePath = URL(filePath: path)

        // Determine target path
        let targetPath = templateLocation.template(name, type: targetLocation)

        // Check if target exists - in MCP mode, we allow overwriting
        let targetExists = fileManager.existsAsLink(targetPath)

        // Create target directory if needed
        let targetDir = templateLocation.templateDir(for: targetLocation)
        if !fileManager.existsAsLink(targetDir) {
            try fileManager.createDirectory(
                at: targetDir,
                withIntermediateDirectories: true,
            )
        }

        // If target exists, remove it first (force mode)
        if targetExists {
            try fileManager.removeItem(at: targetPath)
        }

        do {
            // Copy to target location
            try fileManager.copyItem(at: sourcePath, to: targetPath)

            // Remove source
            try fileManager.removeItem(at: sourcePath)

            return MoveResult(
                name: name,
                sourceLocation: sourceLocation.name,
                targetLocation: targetLocation.name,
                newPath: targetPath.path(percentEncoded: false),
            )
        } catch {
            throw Error.moveFailed(name: name, underlying: error)
        }
    }

    private func runInteractiveMode() async throws {
        // Select template to move
        let options = try await templatesFinder.listWithLocations()

        guard !options.isEmpty else {
            throw Error.noTemplatesFound
        }

        let selectedOption = noora.singleChoicePrompt(
            title: "Select Template to Move",
            question: "Which template would you like to move?",
            options: options,
            description: "Select a template to move.",
        )

        let templateName = selectedOption.template.config.name
        let sourcePath = selectedOption.template.path
        let sourceLocation = selectedOption.location

        // Select target location
        let targetLocation = try selectTargetLocation(
            templateName: templateName,
            sourceLocation: sourceLocation,
        )

        // Move the template
        try await moveTemplate(
            name: templateName,
            sourcePath: sourcePath,
            sourceLocation: sourceLocation,
            targetLocation: targetLocation,
        )
    }

    private func runSelectTargetMode(
        name: String,
        path: URL,
        sourceLocation: TemplateLocationType,
    ) async throws {
        // Select target location
        let targetLocation = try selectTargetLocation(
            templateName: name,
            sourceLocation: sourceLocation,
        )

        // Move the template
        try await moveTemplate(
            name: name,
            sourcePath: path,
            sourceLocation: sourceLocation,
            targetLocation: targetLocation,
        )
    }

    private func selectTargetLocation(
        templateName: String,
        sourceLocation: TemplateLocationType,
    ) throws -> TemplateLocationType {
        let globalOption = TemplateLocationType.global
        let projectOption = TemplateLocationType.project(
            projectDirectory,
            workingDirectory: workingDirectory,
        )

        // Filter out the source location
        let targetOptions: [TemplateLocationType] = if sourceLocation.name == "global" {
            [projectOption]
        } else {
            [globalOption]
        }

        guard !targetOptions.isEmpty else {
            throw Error.noAvailableTargets
        }

        // If only one option, use it
        if targetOptions.count == 1 {
            return targetOptions[0]
        }

        // Prompt for selection
        return noora.singleChoicePrompt(
            title: "Select Target Location",
            question: "Where would you like to move '\(templateName)'?",
            options: targetOptions,
            description: "Select the target location.",
        )
    }

    private func moveTemplate(
        name: String,
        sourcePath: URL,
        sourceLocation: TemplateLocationType,
        targetLocation: TemplateLocationType,
    ) async throws {
        // Determine target path
        let targetPath = templateLocation.template(name, type: targetLocation)

        // Check if target exists
        let targetExists = fileManager.existsAsLink(targetPath)

        if targetExists, !force {
            throw Error.targetAlreadyExists(name: name, location: targetLocation.name)
        }

        // Create target directory if needed
        let targetDir = templateLocation.templateDir(for: targetLocation)
        if !fileManager.existsAsLink(targetDir) {
            try fileManager.createDirectory(
                at: targetDir,
                withIntermediateDirectories: true,
            )
        }

        // If target exists and force is true, remove it first
        if targetExists {
            try fileManager.removeItem(at: targetPath)
        }

        do {
            // Copy to target location
            try fileManager.copyItem(at: sourcePath, to: targetPath)

            // Remove source
            try fileManager.removeItem(at: sourcePath)

            noora.success("Successfully moved template '\(name)' from \(sourceLocation.name) to \(targetLocation.name)")
        } catch {
            throw Error.moveFailed(name: name, underlying: error)
        }
    }

    enum Error: LocalizedError {
        case noTemplatesFound
        case noAvailableTargets
        case targetAlreadyExists(name: String, location: String)
        case moveFailed(name: String, underlying: Swift.Error)

        var errorDescription: String? {
            switch self {
            case .noTemplatesFound:
                "No templates found to move"
            case .noAvailableTargets:
                "No available target locations"
            case let .targetAlreadyExists(name, location):
                "Template '\(name)' already exists in \(location). Use --force to overwrite"
            case let .moveFailed(name, underlying):
                "Failed to move template '\(name)': \(underlying.localizedDescription)"
            }
        }
    }
}

package enum MoveRunnerMode: Codable {
    case interactive
    case selectTarget(name: String, path: String, sourceLocation: TemplateLocationType)
    case direct(
        name: String,
        path: String,
        sourceLocation: TemplateLocationType,
        targetLocation: TemplateLocationType,
    )
    case mcp(
        name: String,
        path: String,
        sourceLocation: TemplateLocationType,
        targetLocation: TemplateLocationType,
    )
}
