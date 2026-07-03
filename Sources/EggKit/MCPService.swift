import FileManagerProtocol
import Foundation
import ProcessRunning

/// Public API for MCP server integration.
/// Provides high-level methods that MCP handlers can use without accessing internal types.
public struct MCPService: Sendable {
    private let fileManager: any FileManagerProtocol
    private let workingDirectory: URL
    private let homeDirectory: URL
    private let projectDirectory: URL
    private let additionalSearchPaths: [URL]

    public init(
        fileManager: any FileManagerProtocol = FileManager.default,
        workingDirectory: URL? = nil,
        projectDirectory: URL? = nil,
        homeDirectory: URL? = nil,
        additionalSearchPaths: [URL] = [],
    ) {
        self.fileManager = fileManager
        self.workingDirectory = workingDirectory ?? URL(filePath: FileManager.default.currentDirectoryPath)
        self.homeDirectory = homeDirectory ?? FileManager.default.homeDirectoryForCurrentUser
        self.projectDirectory = projectDirectory ?? self.workingDirectory
        self.additionalSearchPaths = additionalSearchPaths
    }

    // MARK: - List Templates

    public func listTemplates(location: String? = nil) async throws -> ListResult {
        let locationType = try parseLocationType(location)

        let runner = ListRunner(
            mode: .mcp(location: locationType),
            projectDirectory: projectDirectory,
            workingDirectory: workingDirectory,
            homeDirectory: homeDirectory,
            additionalSearchPaths: additionalSearchPaths,
            fileManager: fileManager,
        )

        return try await runner.runMcp(location: locationType)
    }

    // MARK: - Template Detail

    public func templateDetail(templateName: String) async throws -> DetailResult {
        let template = try await findTemplate(templateName)
        let location = determineLocation(for: template, templateName: templateName)

        let runner = DetailRunner(
            mode: .mcp(template: template, location: location),
            projectDirectory: projectDirectory,
            workingDirectory: workingDirectory,
            homeDirectory: homeDirectory,
            additionalSearchPaths: additionalSearchPaths,
            fileManager: fileManager,
        )

        return runner.runMcp(template: template, location: location)
    }

    // MARK: - Hatch Template

    public func hatchTemplate(
        templateName: String,
        macros: [String: Any],
        outputDirectory: URL? = nil,
        useStaging: Bool = true,
        applyChanges: Bool = true,
        stagingRoot: URL? = nil,
        disableSandbox: Bool = false,
        userConfirmedNoSandbox: Bool = false,
    ) async throws -> HatchResult {
        let outputDir = outputDirectory ?? workingDirectory
        let template = try await findTemplate(templateName, workingDirectory: outputDir)

        // Check if template has sandbox.allowed_paths - require interactive mode or explicit user permission
        if let allowedPaths = template.config.sandbox?.allowedPaths, !allowedPaths.isEmpty {
            throw MCPServiceError.sandboxPermissionRequired(
                paths: allowedPaths,
                templateName: templateName,
            )
        }

        // If sandbox is being disabled, require explicit user confirmation
        if disableSandbox, !userConfirmedNoSandbox {
            throw MCPServiceError.sandboxDisableRequiresConfirmation(templateName: templateName)
        }

        // Convert macros dict to ParsedMacroDefinition array
        let parsedMacros = parseMacros(macros, for: template)

        let runner = HatchRunner(
            mode: .mcp(template: template, parsedMacros: parsedMacros),
            workingDirectory: outputDir,
            homeDirectory: homeDirectory,
            projectDirectory: projectDirectory,
            additionalSearchPaths: additionalSearchPaths,
            fileManager: fileManager,
            processRunner: ProcessRunner(),
            useStaging: useStaging,
            overrideConflicts: true,
            sandboxDisabled: disableSandbox && userConfirmedNoSandbox,
            applyChanges: applyChanges,
            stagingRoot: stagingRoot,
        )

        return try await runner.runMcp(template: template, parsedMacros: parsedMacros)
    }

    public func previewHatchTemplate(
        templateName: String,
        macros: [String: Any],
        outputDirectory: URL? = nil,
        stagingRoot _: URL? = nil,
        include: [String] = [],
        exclude: [String] = [],
        includeDiff: Bool = false,
    ) async throws -> AgentHatchPreviewResult {
        let outputDir = outputDirectory ?? workingDirectory
        let template = try await findTemplate(templateName, workingDirectory: outputDir)
        let parsedMacros = parseMacros(macros, for: template)
        return try await preview(template: template, parsedMacros: parsedMacros, outputDir: outputDir, include: include, exclude: exclude, includeDiff: includeDiff)
    }

    /// Previews a hatch from raw CLI macro arguments (e.g. `["--name", "App"]`).
    ///
    /// Routes the arguments through the same `MacrosParser` the human flow uses,
    /// so CLI flags like `--module-name` normalize to `___MODULE_NAME___` exactly
    /// as the usage contract's example command advertises — there is a single
    /// macro-parsing path, not a transaction-specific reimplementation.
    public func previewHatchTemplate(
        templateName: String,
        macroArguments: [String],
        outputDirectory: URL? = nil,
        include: [String] = [],
        exclude: [String] = [],
        includeDiff: Bool = false,
    ) async throws -> AgentHatchPreviewResult {
        let outputDir = outputDirectory ?? workingDirectory
        let template = try await findTemplate(templateName, workingDirectory: outputDir)
        let parsedMacros = try MacrosParser(macroDefinitions: template.config.macros ?? [])
            .parseCommandLineArguments(macroArguments)
        return try await preview(template: template, parsedMacros: parsedMacros, outputDir: outputDir, include: include, exclude: exclude, includeDiff: includeDiff)
    }

    public func applyHatchTransaction(
        applyToken: String,
        workingDirectory: URL? = nil,
        force: Bool = false,
    ) async throws -> AgentHatchApplyResult {
        let outputDir = workingDirectory ?? self.workingDirectory
        let runner = AgentHatchTransactionRunner(
            fileManager: fileManager,
            workingDirectory: outputDir,
            homeDirectory: homeDirectory,
            templateDirectory: outputDir,
            config: Config(
                name: "transaction",
                description: "Existing hatch transaction",
                hatch: .init(output: "."),
            ),
            parsedMacros: [],
        )

        return try await runner.apply(token: applyToken, force: force)
    }

    public func discardHatchTransaction(
        applyToken: String,
        workingDirectory: URL? = nil,
    ) async throws -> AgentHatchApplyResult {
        let outputDir = workingDirectory ?? self.workingDirectory
        let runner = AgentHatchTransactionRunner(
            fileManager: fileManager,
            workingDirectory: outputDir,
            homeDirectory: homeDirectory,
            templateDirectory: outputDir,
            config: Config(
                name: "transaction",
                description: "Existing hatch transaction",
                hatch: .init(output: "."),
            ),
            parsedMacros: [],
        )

        return try await runner.discard(token: applyToken)
    }

    public func rollbackHatchTransaction(
        rollbackId: String,
        workingDirectory: URL? = nil,
        force: Bool = false,
    ) async throws -> AgentHatchRollbackResult {
        let outputDir = workingDirectory ?? self.workingDirectory
        let runner = AgentHatchTransactionRunner(
            fileManager: fileManager,
            workingDirectory: outputDir,
            homeDirectory: homeDirectory,
            templateDirectory: outputDir,
            config: Config(
                name: "transaction",
                description: "Existing hatch transaction",
                hatch: .init(output: "."),
            ),
            parsedMacros: [],
        )

        return try await runner.rollback(id: rollbackId, force: force)
    }

    // MARK: - Create Template

    public func createTemplate(
        name: String,
        description: String,
        location: String,
    ) async throws -> CreateResult {
        let locationKind = try parseLocationKind(location)

        let runner = CreateRunner(
            mode: .mcp(name: name, description: description, location: locationKind),
            skipConfig: false,
            projectDirectory: projectDirectory,
            workingDirectory: workingDirectory,
            homeDirectory: homeDirectory,
            fileManager: fileManager,
        )

        return try await runner.runMcp(name: name, description: description, location: locationKind)
    }

    // MARK: - Delete Template

    public func deleteTemplate(templateName: String) async throws -> DeleteResult {
        let template = try await findTemplate(templateName)
        let location = determineLocation(for: template, templateName: templateName)

        let runner = DeleteRunner(
            mode: .mcp(name: templateName, path: template.path.path(percentEncoded: false), location: location),
            force: true,
            projectDirectory: projectDirectory,
            workingDirectory: workingDirectory,
            homeDirectory: homeDirectory,
            additionalSearchPaths: additionalSearchPaths,
            fileManager: fileManager,
        )

        return try runner.runMcp(
            name: templateName,
            path: template.path.path(percentEncoded: false),
            location: location,
        )
    }

    // MARK: - Duplicate Template

    public func duplicateTemplate(
        sourceName: String,
        newName: String,
        newDescription: String? = nil,
    ) async throws -> DuplicateResult {
        let sourceTemplate = try await findTemplate(sourceName)
        let sourceLocation = determineLocation(for: sourceTemplate, templateName: sourceName)
        let finalDescription = newDescription ?? sourceTemplate.config.description

        let runner = DuplicateRunner(
            mode: .mcp(
                sourceName: sourceName,
                sourcePath: sourceTemplate.path.path(percentEncoded: false),
                sourceLocation: sourceLocation,
                newName: newName,
                newDescription: finalDescription,
            ),
            projectDirectory: projectDirectory,
            workingDirectory: workingDirectory,
            homeDirectory: homeDirectory,
            additionalSearchPaths: additionalSearchPaths,
            fileManager: fileManager,
        )

        return try await runner.runMcp(
            sourceName: sourceName,
            sourcePath: sourceTemplate.path.path(percentEncoded: false),
            sourceLocation: sourceLocation,
            newName: newName,
            newDescription: finalDescription,
        )
    }

    // MARK: - Move Template

    public func moveTemplate(
        templateName: String,
        targetLocation: String,
    ) async throws -> MoveResult {
        let target = try parseLocationType(targetLocation, required: true)!
        let sourceTemplate = try await findTemplate(templateName)
        let sourceLocation = determineLocation(for: sourceTemplate, templateName: templateName)

        let runner = MoveRunner(
            mode: .mcp(
                name: templateName,
                path: sourceTemplate.path.path(percentEncoded: false),
                sourceLocation: sourceLocation,
                targetLocation: target,
            ),
            force: true,
            projectDirectory: projectDirectory,
            workingDirectory: workingDirectory,
            homeDirectory: homeDirectory,
            additionalSearchPaths: additionalSearchPaths,
            fileManager: fileManager,
        )

        return try await runner.runMcp(
            name: templateName,
            path: sourceTemplate.path.path(percentEncoded: false),
            sourceLocation: sourceLocation,
            targetLocation: target,
        )
    }

    // MARK: - Validate Template

    public func validateTemplate(templatePath: String) async throws -> ValidateResult {
        let path = URL(filePath: templatePath)
        let configLoader = ConfigLoader(fileManager: fileManager)
        let config = try configLoader.load(from: path)

        let runner = ValidateRunner(
            mode: .mcp(config: config, templatePath: path),
            fileManager: fileManager,
        )

        return await runner.runMcp(config: config, templatePath: path)
    }

    // MARK: - Install Templates

    public func installTemplates(
        source: String,
        location: String,
        ref: String? = nil,
        include: [String]? = nil,
        exclude: [String]? = nil,
    ) async throws -> InstallResult {
        let locationKind = try parseLocationKind(location)
        let templateSource = try parseTemplateSource(source, ref: ref)
        let filter = parseTemplateFilter(include: include, exclude: exclude)

        let runner = InstallRunner(
            mode: .direct(source: templateSource, location: locationKind, filter: filter),
            force: true,
            projectDirectory: projectDirectory,
            workingDirectory: workingDirectory,
            homeDirectory: homeDirectory,
            fileManager: fileManager,
        )

        return try await runner.run()
    }

    // MARK: - Private Helpers

    /// Creates a TemplatesFinder with the service's configuration.
    private func preview(
        template: Template,
        parsedMacros: [ParsedMacroDefinition],
        outputDir: URL,
        include: [String],
        exclude: [String],
        includeDiff: Bool,
    ) async throws -> AgentHatchPreviewResult {
        let runner = AgentHatchTransactionRunner(
            fileManager: fileManager,
            workingDirectory: outputDir,
            homeDirectory: homeDirectory,
            templateDirectory: template.path,
            config: template.config,
            parsedMacros: parsedMacros,
            include: include,
            exclude: exclude,
        )

        return try await runner.preview(includeDiff: includeDiff)
    }

    private func makeTemplatesFinder(workingDirectory: URL? = nil) -> TemplatesFinder {
        TemplatesFinder(
            fileManager: fileManager,
            projectDirectory: projectDirectory,
            workingDirectory: workingDirectory ?? self.workingDirectory,
            homeDirectory: homeDirectory,
            additionalSearchPaths: additionalSearchPaths,
        )
    }

    /// Finds a template by name.
    private func findTemplate(_ name: String, workingDirectory: URL? = nil) async throws -> Template {
        try await makeTemplatesFinder(workingDirectory: workingDirectory).fetchTemplate(name)
    }

    /// Determines the location type for a template.
    private func determineLocation(for template: Template, templateName: String) -> TemplateLocationType {
        TemplateLocation(homeDirectory: homeDirectory)
            .determineLocation(
                templateName: templateName,
                templatePath: template.path,
                additionalSearchPaths: additionalSearchPaths,
                projectDirectory: projectDirectory,
                workingDirectory: workingDirectory,
            )
    }

    /// Parses a location string to TemplateLocationType.
    private func parseLocationType(_ location: String?, required: Bool = false) throws -> TemplateLocationType? {
        guard let location else { return nil }

        switch location {
        case "global":
            return .global
        case "project":
            return .project(projectDirectory, workingDirectory: workingDirectory)
        default:
            if required {
                throw MCPServiceError.invalidLocation(location)
            }
            return nil
        }
    }

    /// Parses a location string to TemplateLocationType.Kind.
    private func parseLocationKind(_ location: String) throws -> TemplateLocationType.Kind {
        switch location {
        case "global":
            return .global
        case "project":
            return .project
        default:
            throw MCPServiceError.invalidLocation(location)
        }
    }

    /// Parses source string to TemplateSource.
    private func parseTemplateSource(_ source: String, ref: String?) throws -> TemplateSource {
        if source.hasPrefix("http://") || source.hasPrefix("https://") || source.contains("@") {
            guard let gitURL = GitURLParser().parse(source) else {
                throw MCPServiceError.invalidGitURL(source)
            }
            // MCP uses ref as branch name (most common case)
            let gitRef: GitRef? = ref.map { .branch($0) }
            return .git(url: gitURL, ref: gitRef)
        } else {
            return .local(path: URL(filePath: source))
        }
    }

    /// Parses include/exclude filters to TemplateFilter.
    private func parseTemplateFilter(include: [String]?, exclude: [String]?) -> TemplateFilter {
        if let include, !include.isEmpty {
            .include(include)
        } else if let exclude, !exclude.isEmpty {
            .exclude(exclude)
        } else {
            .none
        }
    }

    /// Converts macro dictionary to ParsedMacroDefinition array.
    ///
    /// The input `macros` dict keys must be in `___UPPER_SNAKE_CASE___` format.
    /// Example: `{"___MODULE_NAME___": "MyModule", "___INCLUDE_TESTS___": "true"}`
    private func parseMacros(_ macros: [String: Any], for template: Template) -> [ParsedMacroDefinition] {
        guard let macroDefinitions = template.config.macros else {
            return []
        }

        return macroDefinitions.compactMap { macro in
            // macro.name is in ___UPPER_SNAKE_CASE___ format
            let macroName = macro.name

            guard let value = macros[macroName] else {
                if let defaultValue = macro.default {
                    return ParsedMacroDefinition(macro: macroName, values: defaultValue.asStringArray)
                }
                return nil
            }

            let values: [String] = if let stringValue = value as? String {
                [stringValue]
            } else if let boolValue = value as? Bool {
                [String(boolValue)]
            } else if let arrayValue = value as? [String] {
                arrayValue
            } else {
                [String(describing: value)]
            }

            return ParsedMacroDefinition(macro: macroName, values: values)
        }
    }
}

// MARK: - Errors

public enum MCPServiceError: Error, LocalizedError, Sendable {
    case invalidLocation(String)
    case invalidGitURL(String)
    case sandboxPermissionRequired(paths: [String], templateName: String)
    case sandboxDisableRequiresConfirmation(templateName: String)

    public var errorDescription: String? {
        switch self {
        case let .invalidLocation(location):
            "Invalid location '\(location)'. Must be 'global' or 'project'."
        case let .invalidGitURL(url):
            "Invalid Git URL: \(url)"
        case let .sandboxPermissionRequired(paths, templateName):
            """
            ⚠️ SANDBOX EXTENDED WRITE ACCESS REQUIRED

            This template requires write access to paths outside the sandbox:
            \(paths.map { "  - \($0)" }.joined(separator: "\n"))

            To proceed:
            1. Run in interactive mode: egg hatch \(templateName)
            2. Or use --no-sandbox flag with explicit user permission

            MCP/direct mode cannot grant extended sandbox permissions automatically.
            """
        case let .sandboxDisableRequiresConfirmation(templateName):
            """
            ⚠️ SANDBOX DISABLED: This operation will run without filesystem restrictions.

            Before proceeding, please confirm with the user that they approve running
            'egg hatch' without sandbox protection for template: \(templateName)

            If user approves, call this tool again with 'userConfirmedNoSandbox: true'
            """
        }
    }
}

// MARK: - Helper Extension

extension Config.MacroDefaultValue {
    var asStringArray: [String] {
        switch self {
        case let .string(value):
            [value]
        case let .array(values):
            values
        }
    }
}
