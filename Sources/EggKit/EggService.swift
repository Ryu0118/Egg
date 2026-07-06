import FileManagerProtocol
import Foundation
import ProcessRunning

/// The application-service facade shared by every egg frontend.
///
/// Both the CLI (for its JSON-emitting paths: the hatch transaction flow and
/// `--json` template commands) and the MCP server call these use-case methods
/// and encode the same Codable result models — one source of truth for
/// behavior and output shape, regardless of which frontend invoked it.
public struct EggService: Sendable {
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
            // Skipped-template diagnostics must not interleave with the JSON
            // body this path exists to emit.
            interaction: SilentInteraction(),
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
        allowLargeStaging: Bool = false,
        allowNonGitStaging: Bool = false,
    ) async throws -> HatchResult {
        let outputDir = outputDirectory ?? workingDirectory
        let template = try await findTemplate(templateName, workingDirectory: outputDir)

        // If sandbox is being disabled, require explicit user confirmation
        if disableSandbox, !userConfirmedNoSandbox {
            throw EggServiceError.sandboxDisableRequiresConfirmation(templateName: templateName)
        }

        // Check if template has sandbox.allowed_paths - require interactive mode or explicit user permission
        if !disableSandbox,
           let allowedPaths = template.config.sandbox?.allowedPaths,
           !allowedPaths.isEmpty
        {
            throw EggServiceError.sandboxPermissionRequired(
                paths: allowedPaths,
                templateName: templateName,
            )
        }

        // Service mode has no prompt channel — reaching one exits the
        // process, killing the MCP server mid-request — so every consent the
        // human flow collects interactively is collected here, up front, as
        // parameters: staging a non-git directory (copies everything, no
        // .gitignore filtering) needs allow_non_git_staging, and a clone
        // above the size guard needs allow_large_staging. The refusals carry
        // the resolved directory and its measured size so the caller can
        // inspect the facts and decide. With the checks done, the runner is
        // told consent is pre-collected and the prompts stay unreachable.
        if useStaging {
            let stagingBase = stagingRoot ?? outputDir
            let preflight = StagingPreflight(fileManager: fileManager)
            if await GitRepositoryChecker(processRunner: ProcessRunner()).isGitRepository(stagingBase) {
                if !allowLargeStaging {
                    let fileCount = try await preflight.countGitCloneableFiles(in: stagingBase)
                    guard fileCount <= StagingPreflight.defaultFileLimit else {
                        throw EggServiceError.stagedHatchTooLarge(
                            path: stagingBase.path(percentEncoded: false),
                            fileCount: fileCount,
                            limit: StagingPreflight.defaultFileLimit,
                        )
                    }
                }
            } else {
                let (fileCount, isExact) = preflight.countAllFiles(in: stagingBase)
                guard allowNonGitStaging else {
                    throw EggServiceError.stagedHatchRequiresGitRepository(
                        path: stagingBase.path(percentEncoded: false),
                        fileCount: fileCount,
                        isExact: isExact,
                    )
                }
                guard fileCount <= StagingPreflight.defaultFileLimit || allowLargeStaging else {
                    throw EggServiceError.stagedHatchTooLarge(
                        path: stagingBase.path(percentEncoded: false),
                        fileCount: fileCount,
                        limit: StagingPreflight.defaultFileLimit,
                    )
                }
            }
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
            // Progress banners must not interleave with the JSON-RPC stream —
            // '🔒 Creating staging workspace…' on stdout corrupts the protocol
            // before the client sees any response.
            interaction: SilentInteraction(),
            useStaging: useStaging,
            overrideConflicts: true,
            sandboxDisabled: disableSandbox && userConfirmedNoSandbox,
            applyChanges: applyChanges,
            stagingRoot: stagingRoot,
            stagingConsentPrecollected: true,
        )

        return try await runner.runMcp(template: template, parsedMacros: parsedMacros)
    }

    public func previewHatchTemplate(
        templateName: String,
        macros: [String: Any],
        outputDirectory: URL? = nil,
        stagingRoot: URL? = nil,
        include: [String] = [],
        exclude: [String] = [],
        includeDiff: Bool = false,
        disableSandbox: Bool = false,
        userConfirmedNoSandbox: Bool = false,
        allowedWritePaths: [String] = [],
        allowLargeStaging: Bool = false,
        allowNonGitStaging: Bool = false,
    ) async throws -> AgentHatchPreviewResult {
        let outputDir = outputDirectory ?? workingDirectory
        let template = try await findTemplate(templateName, workingDirectory: outputDir)
        try validateSandboxDisable(
            disableSandbox,
            userConfirmedNoSandbox: userConfirmedNoSandbox,
            templateName: templateName,
        )
        let parsedMacros = parseMacros(macros, for: template)
        return try await preview(
            template: template,
            parsedMacros: parsedMacros,
            outputDir: outputDir,
            stagingRoot: stagingRoot,
            include: include,
            exclude: exclude,
            includeDiff: includeDiff,
            sandboxDisabled: disableSandbox && userConfirmedNoSandbox,
            allowedWritePaths: allowedWritePaths,
            allowLargeStaging: allowLargeStaging,
            allowNonGitStaging: allowNonGitStaging,
        )
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
        sandboxDisabled: Bool = false,
        allowedWritePaths: [String] = [],
        allowLargeStaging: Bool = false,
        allowNonGitStaging: Bool = false,
    ) async throws -> AgentHatchPreviewResult {
        let outputDir = outputDirectory ?? workingDirectory
        let template = try await findTemplate(templateName, workingDirectory: outputDir)
        let parsedMacros = try MacrosParser(macroDefinitions: template.config.macros ?? [])
            .parseCommandLineArguments(macroArguments)
        return try await preview(
            template: template,
            parsedMacros: parsedMacros,
            outputDir: outputDir,
            include: include,
            exclude: exclude,
            includeDiff: includeDiff,
            sandboxDisabled: sandboxDisabled,
            allowedWritePaths: allowedWritePaths,
            allowLargeStaging: allowLargeStaging,
            allowNonGitStaging: allowNonGitStaging,
        )
    }

    public func applyHatchTransaction(
        applyToken: String,
        workingDirectory: URL? = nil,
        force: Bool = false,
    ) async throws -> AgentHatchApplyResult {
        try await makeTransactionRunner(workingDirectory: workingDirectory)
            .apply(token: applyToken, force: force)
    }

    public func discardHatchTransaction(
        applyToken: String,
        workingDirectory: URL? = nil,
        force: Bool = false,
    ) async throws -> AgentHatchDiscardResult {
        try await makeTransactionRunner(workingDirectory: workingDirectory)
            .discard(token: applyToken, force: force)
    }

    public func rollbackHatchTransaction(
        rollbackId: String,
        workingDirectory: URL? = nil,
        force: Bool = false,
    ) async throws -> AgentHatchRollbackResult {
        try await makeTransactionRunner(workingDirectory: workingDirectory)
            .rollback(id: rollbackId, force: force)
    }

    public func listHatchTransactions(
        workingDirectory: URL? = nil,
        includeSizes: Bool = false,
    ) -> AgentHatchTransactionsResult {
        makeTransactionRunner(workingDirectory: workingDirectory).transactions(includeSizes: includeSizes)
    }

    /// Runner for operating on an already-persisted transaction: apply,
    /// rollback, and discard only read state under `.egg/`, so they need no
    /// template or macros — just the working directory.
    private func makeTransactionRunner(workingDirectory: URL?) -> AgentHatchTransactionRunner {
        let outputDir = workingDirectory ?? self.workingDirectory
        return AgentHatchTransactionRunner(
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
        let config: Config
        do {
            config = try configLoader.load(from: path)
        } catch let error as ConfigLoaderError {
            // An undecodable config is a validation *result*, not a tool
            // failure: report it as invalid with the formatted decode
            // message. A missing config.yml stays a thrown error — that's a
            // wrong path, not a broken template.
            guard case .decodingFailed = error else { throw error }
            return ValidateResult(
                templateName: path.lastPathComponent,
                templatePath: path.path(percentEncoded: false),
                isValid: false,
                errors: [error.localizedDescription],
            )
        }

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
            // Direct mode logs progress lines; the service's callers put the
            // encoded result on stdout, which must not be interleaved.
            interaction: SilentInteraction(),
        )

        return try await runner.run()
    }

    // MARK: - Private Helpers

    /// Creates a TemplatesFinder with the service's configuration.
    private func preview(
        template: Template,
        parsedMacros: [ParsedMacroDefinition],
        outputDir: URL,
        stagingRoot: URL? = nil,
        include: [String],
        exclude: [String],
        includeDiff: Bool,
        sandboxDisabled: Bool,
        allowedWritePaths: [String] = [],
        allowLargeStaging: Bool = false,
        allowNonGitStaging: Bool = false,
    ) async throws -> AgentHatchPreviewResult {
        let runner = AgentHatchTransactionRunner(
            fileManager: fileManager,
            // stagingRoot means the same as in the direct flow: the directory
            // the staging clones from and applies back into. The transaction
            // records (.egg) live there too, so a follow-up apply must name
            // it as its working_directory.
            workingDirectory: stagingRoot ?? outputDir,
            homeDirectory: homeDirectory,
            templateDirectory: template.path,
            config: template.config,
            parsedMacros: parsedMacros,
            include: include,
            exclude: exclude,
            sandboxDisabled: sandboxDisabled,
            allowedWritePaths: allowedWritePaths,
            allowLargeStaging: allowLargeStaging,
            allowNonGitStaging: allowNonGitStaging,
        )

        return try await runner.preview(includeDiff: includeDiff)
    }

    private func validateSandboxDisable(
        _ disableSandbox: Bool,
        userConfirmedNoSandbox: Bool,
        templateName: String,
    ) throws {
        if disableSandbox, !userConfirmedNoSandbox {
            throw EggServiceError.sandboxDisableRequiresConfirmation(templateName: templateName)
        }
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
                throw EggServiceError.invalidLocation(location)
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
            throw EggServiceError.invalidLocation(location)
        }
    }

    /// Parses source string to TemplateSource.
    private func parseTemplateSource(_ source: String, ref: String?) throws -> TemplateSource {
        // GitURLParser knows every supported scheme (https, ssh, git, file,
        // credentialed); anything it can't parse is a local filesystem path.
        if let gitURL = GitURLParser().parse(source) {
            return .git(url: gitURL, ref: ref.map(Self.gitRef(from:)))
        }
        // Local sources copy the working tree as-is, so a ref cannot be
        // honored — reject it loudly (matching the CLI validator) instead of
        // silently installing HEAD when the caller believes they pinned one.
        guard ref == nil else {
            throw EggServiceError.refNotAllowedForLocalPath(source)
        }
        return .local(path: URL(filePath: source))
    }

    /// Maps the service's single `ref` string onto a GitRef: a 40-hex string
    /// is a commit SHA; anything else works as `--branch`, which git accepts
    /// for both branches and tags.
    private static func gitRef(from ref: String) -> GitRef {
        let isCommitSHA = ref.count == 40 && ref.allSatisfy(\.isHexDigit)
        return isCommitSHA ? .revision(ref) : .branch(ref)
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

public enum EggServiceError: Error, LocalizedError, Sendable {
    case invalidLocation(String)
    case invalidGitURL(String)
    case refNotAllowedForLocalPath(String)
    case sandboxPermissionRequired(paths: [String], templateName: String)
    case sandboxDisableRequiresConfirmation(templateName: String)
    case stagedHatchRequiresGitRepository(path: String, fileCount: Int, isExact: Bool)
    case stagedHatchTooLarge(path: String, fileCount: Int, limit: Int)

    public var errorDescription: String? {
        switch self {
        case let .invalidLocation(location):
            "Invalid location '\(location)'. Must be 'global' or 'project'."
        case let .stagedHatchRequiresGitRepository(path, fileCount, isExact):
            "'\(path)' is not a git repository. A staged hatch would copy all \(fileCount)\(isExact ? "" : "+") files in that directory — no .gitignore filtering, so build artifacts and caches are included — twice. Recommended: run 'git init' in '\(path)' so staging follows .gitignore. To proceed anyway, pass allow_non_git_staging: true (a count above the size guard additionally needs allow_large_staging: true), or pass use_staging: false to write directly (no preview or rollback)."
        case let .stagedHatchTooLarge(path, fileCount, limit):
            "Staging '\(path)' would clone \(fileCount) files (guard limit: \(limit)) — twice. Scope it down with staging_root pointing at a smaller directory, pass allow_large_staging: true to proceed anyway, or pass use_staging: false to write directly."
        case let .invalidGitURL(url):
            "Invalid Git URL: \(url)"
        case let .refNotAllowedForLocalPath(source):
            "A git ref cannot be used with the local path '\(source)': local sources copy the directory as-is. Use a git URL (e.g. file://\(source)) to install from a specific branch, tag, or commit."
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
            SANDBOX DISABLED CONFIRMATION REQUIRED

            Ask the user whether to run 'egg hatch' without sandbox protection for template: \(templateName)
            Do not classify the script contents yourself; require explicit user approval.

            If user approves, call this tool again with 'user_confirmed_no_sandbox: true'
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

@available(*, deprecated, renamed: "EggService", message: "MCPService was renamed: it is the shared application service for every frontend (CLI and MCP), not MCP-specific.")
public typealias MCPService = EggService

@available(*, deprecated, renamed: "EggServiceError")
public typealias MCPServiceError = EggServiceError
