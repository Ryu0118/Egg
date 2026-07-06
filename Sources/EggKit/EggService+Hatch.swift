import FileManagerProtocol
import Foundation
import ProcessRunning

/// The hatch/preview/apply/rollback/discard transaction flow. Each method
/// resolves a `Template`, then hands off to `HatchRunner` or
/// `AgentHatchTransactionRunner` — see `EggService.swift`'s doc comment.
public extension EggService {
    // MARK: - Hatch Template

    func hatchTemplate(
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
        // above the size guard needs allow_large_staging. The decision itself
        // is StagingFeasibility, shared with AgentHatchTransactionRunner's
        // agent-facing preview() so the two entry points can't drift on what
        // "too large" or "needs consent" means. With the check done, the
        // runner is told consent is pre-collected and its own (prompt-based)
        // check stays unreachable.
        if useStaging {
            let stagingBase = stagingRoot ?? outputDir
            let feasibility = StagingFeasibility(fileManager: fileManager)
            let processRunner = ProcessRunner()
            let facts = try await feasibility.facts(for: stagingBase, processRunner: processRunner)
            switch feasibility.decide(facts: facts, allowLargeStaging: allowLargeStaging, allowNonGitStaging: allowNonGitStaging) {
            case .proceed:
                break
            case let .nonGitConsentRequired(fileCount, isExact):
                throw EggServiceError.stagedHatchRequiresGitRepository(
                    path: stagingBase.path(percentEncoded: false),
                    fileCount: fileCount,
                    isExact: isExact,
                )
            case let .tooLarge(fileCount, limit):
                throw EggServiceError.stagedHatchTooLarge(
                    path: stagingBase.path(percentEncoded: false),
                    fileCount: fileCount,
                    limit: limit,
                )
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

    func previewHatchTemplate(
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
    func previewHatchTemplate(
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

    func applyHatchTransaction(
        applyToken: String,
        workingDirectory: URL? = nil,
        force: Bool = false,
    ) async throws -> AgentHatchApplyResult {
        try await makeTransactionRunner(workingDirectory: workingDirectory)
            .apply(token: applyToken, force: force)
    }

    func discardHatchTransaction(
        applyToken: String,
        workingDirectory: URL? = nil,
        force: Bool = false,
    ) async throws -> AgentHatchDiscardResult {
        try await makeTransactionRunner(workingDirectory: workingDirectory)
            .discard(token: applyToken, force: force)
    }

    func rollbackHatchTransaction(
        rollbackId: String,
        workingDirectory: URL? = nil,
        force: Bool = false,
    ) async throws -> AgentHatchRollbackResult {
        try await makeTransactionRunner(workingDirectory: workingDirectory)
            .rollback(id: rollbackId, force: force)
    }

    func listHatchTransactions(
        workingDirectory: URL? = nil,
        includeSizes: Bool = false,
    ) -> AgentHatchTransactionsResult {
        makeTransactionRunner(workingDirectory: workingDirectory).transactions(includeSizes: includeSizes)
    }

    // MARK: - Shared Helpers

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
