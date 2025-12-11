import FileSystem
import Foundation
import Noora
import Path
import ProcessRunning

/// Orchestrates the complete lifecycle workflow with atomic all-or-nothing execution.
///
/// TransactionalWorkflowRunner executes all phases in a transactional workspace (APFS clone of working directory),
/// then applies only the changed files to the real working directory on success.
/// This provides:
/// - **Atomic execution**: Either all changes apply or none do
/// - **Safety**: Failed runs don't leave partial changes
/// - **Conflict detection**: Warns about concurrent modifications
/// - **User confirmation**: Shows change summary before applying (unless `force=true`)
///
/// Example:
/// ```swift
/// let runner = TransactionalWorkflowRunner(
///     processRunner: ProcessRunner(),
///     fileSystem: FileSystem(),
///     workingDirectory: try AbsolutePath(validating: "/tmp/project"),
///     homeDirectory: try AbsolutePath(validating: NSHomeDirectory()),
///     noora: Noora(),
///     isInteractive: true,
///     force: false
/// )
///
/// let outputPath = try await runner.run(
///     config: config,
///     macros: resolvedMacros,
///     templateDirectory: templateDir
/// )
/// ```
struct TransactionalWorkflowRunner: WorkflowRunning {
    private let processRunner: any ProcessRunning
    private let fileSystem: any FileSysteming
    private let workingDirectory: AbsolutePath
    private let homeDirectory: AbsolutePath
    private let noora: any Noorable
    private let isInteractive: Bool
    private let force: Bool
    private let phaseRunner: PhaseRunner
    private let workspaceWatcher: any DirectoryWatching
    private let workingDirectoryWatcher: any DirectoryWatching

    init(
        processRunner: any ProcessRunning,
        fileSystem: any FileSysteming,
        workingDirectory: AbsolutePath,
        homeDirectory: AbsolutePath,
        noora: some Noorable = Noora(),
        isInteractive: Bool = true,
        force: Bool = false,
        workspaceWatcher: some DirectoryWatching = FSEventsDirectoryWatcher(),
        workingDirectoryWatcher: some DirectoryWatching = FSEventsDirectoryWatcher()
    ) {
        self.processRunner = processRunner
        self.fileSystem = fileSystem
        self.workingDirectory = workingDirectory
        self.homeDirectory = homeDirectory
        self.noora = noora
        self.isInteractive = isInteractive
        self.force = force
        phaseRunner = PhaseRunner(
            processRunner: processRunner,
            fileSystem: fileSystem,
            homeDirectory: homeDirectory,
            noora: noora,
            isInteractive: isInteractive,
            force: force
        )
        self.workspaceWatcher = workspaceWatcher
        self.workingDirectoryWatcher = workingDirectoryWatcher
    }

    /// Executes the complete lifecycle workflow in a transactional workspace.
    ///
    /// - Parameters:
    ///   - config: Template configuration containing lifecycle steps and hatch configuration
    ///   - macroInputs: Macro inputs to be resolved (either already resolved or pending interactive prompts)
    ///   - templateDirectory: Source directory containing the template files
    /// - Returns: The resolved absolute path of the output directory (in the real working directory)
    /// - Throws: `TransactionalWorkspaceContext.Error` for transactional workspace-related failures, or other errors from phases
    func run(
        config: Config,
        macroInputs: MacroInputs,
        templateDirectory: AbsolutePath
    ) async throws -> AbsolutePath {
        // Step 1: Create transactional workspace (APFS clone of working directory)
        noora.passthrough("🔒 Creating transactional workspace...\n")
        let workspace = try await TransactionalWorkspaceContext.create(
            cloning: workingDirectory,
            homeDirectory: homeDirectory,
            fileSystem: fileSystem,
            workspaceWatcher: workspaceWatcher,
            workingDirectoryWatcher: workingDirectoryWatcher,
            processRunner: processRunner
        )

        // Register cleanup handler for SIGINT/SIGTERM (Control+C)
        let cleanupHandlerId = await TransactionalWorkspaceCleanupRegistry.shared.register {
            await workspace.discard()
        }

        // Ensure cleanup handler is unregistered when we're done
        defer {
            Task {
                await TransactionalWorkspaceCleanupRegistry.shared.unregister(cleanupHandlerId)
            }
        }

        // Ensure transactional workspace is discarded on any failure
        do {
            // Step 2: Resolve macros with workspace root as working directory
            // This is critical for path-type macros to resolve correctly
            let macros = try resolveMacros(macroInputs, config: config, workspaceRoot: workspace.root)

            let outputs = StepOutputsStorage()

            // Step 2: Execute pre_hatch phase in transactional workspace (with OS-level sandboxing)
            let executionEnvironment = ExecutionEnvironment.transactional(
                root: workspace.root,
                originalWorkingDirectory: workingDirectory
            )

            if let preHatchSteps = config.preHatch {
                try await phaseRunner.executePreHatch(
                    steps: preHatchSteps,
                    macros: macros,
                    outputs: outputs,
                    workingDirectory: workspace.root,
                    additionalEnvironment: ["EGG_SANDBOX_ROOT": workspace.root.pathString],
                    executionEnvironment: executionEnvironment
                )
            }

            // Step 4: Execute hatch phase (template expansion) in transactional workspace
            let workspaceOutputDirectory = try await phaseRunner.executeHatch(
                config: config,
                macros: macros,
                outputs: outputs,
                templateDirectory: templateDirectory,
                workingDirectory: workspace.root,
                pathValidator: { path in
                    try await workspace.validatePath(path)
                }
            )

            noora.passthrough("✅ Template hatched successfully in transactional workspace.\n", tab: 1)

            // Calculate relative path for later use
            let resolvedOutputPath = try computeRelativePath(
                outputDirectory: workspaceOutputDirectory,
                workspaceRoot: workspace.root
            )

            // Step 5: Execute post_hatch phase in transactional workspace (with OS-level sandboxing)
            if let postHatchSteps = config.postHatch {
                try await phaseRunner.executePostHatch(
                    steps: postHatchSteps,
                    macros: macros,
                    outputs: outputs,
                    workingDirectory: workspace.root,
                    executionEnvironment: executionEnvironment
                )
            }

            // Step 6: Compute changes and handle conflicts
            let changeSummary = try await workspace.computeChangeSummary()

            if changeSummary.isEmpty {
                noora.passthrough("ℹ️ No changes to apply.\n")
                await workspace.discard()
                return workingDirectory.appending(resolvedOutputPath)
            }

            // Step 7: Display change summary
            displayChangeSummary(changeSummary)

            // Step 8: Handle confirmation based on mode
            try await confirmChanges(workspace: workspace)

            // Step 10: Apply changes to working directory
            noora.passthrough("📦 Applying changes...\n")
            let overriddenConflicts = try await workspace.applyChanges(changeSummary, force: force)

            // Display warning for overridden conflicts (when force=true)
            if !overriddenConflicts.isEmpty {
                noora.passthrough("⚠️ Overwritten conflicting files:\n")
                for conflict in overriddenConflicts {
                    noora.passthrough("- \(conflict.path.pathString) (\(conflict.type.description))\n", tab: 1)
                }
            }

            noora.passthrough("✅ Changes applied successfully!\n")

            // Return path in real working directory
            return workingDirectory.appending(resolvedOutputPath)

        } catch {
            // Ensure transactional workspace is always discarded on error
            await workspace.discard()
            throw error
        }
    }

    /// Computes the relative path from workspace root to output directory.
    ///
    /// - Parameters:
    ///   - outputDirectory: The absolute output path within transactional workspace
    ///   - workspaceRoot: The transactional workspace root path
    /// - Returns: The relative path from workspace root
    private func computeRelativePath(
        outputDirectory: AbsolutePath,
        workspaceRoot: AbsolutePath
    ) throws -> RelativePath {
        // If output is the workspace root itself (output: "."), return "." as the relative path
        if outputDirectory == workspaceRoot {
            return try RelativePath(validating: ".")
        }

        // Remove the workspace root prefix to get the relative path
        let pathString = outputDirectory.pathString
        let rootPrefix = workspaceRoot.pathString + "/"
        guard pathString.hasPrefix(rootPrefix) else {
            throw LifecycleStepError.invalidOutputDirectory(
                "Output path is not within transactional workspace: \(pathString)"
            )
        }
        let relative = String(pathString.dropFirst(rootPrefix.count))
        return try RelativePath(validating: relative)
    }

    /// Handles user confirmation before applying changes.
    ///
    /// Behavior matrix:
    /// - `force=true`: Skip confirmation, apply immediately
    /// - `force=false, isInteractive=true`: Prompt user for confirmation
    /// - `force=false, isInteractive=false, conflicts=empty`: Apply without confirmation
    /// - `force=false, isInteractive=false, conflicts=exists`: Throw error
    private func confirmChanges(workspace: TransactionalWorkspaceContext) async throws {
        guard !force else { return }

        let conflicts = try await workspace.detectConflicts()

        if !conflicts.isEmpty {
            displayConflicts(conflicts)
        }

        if isInteractive {
            let confirmed = noora.yesOrNoChoicePrompt(
                title: "Apply Changes (transactional workspace → current directory)",
                question: "Apply to \(workspace.originalWorkingDirectory.pathString)?"
            )
            guard confirmed else {
                noora.passthrough("❌ Changes discarded by user.\n")
                await workspace.discard()
                throw TransactionalWorkspaceContext.Error.userAborted
            }
        } else if !conflicts.isEmpty {
            await workspace.discard()
            throw TransactionalWorkspaceContext.Error.conflictingFiles(conflicts)
        }
    }

    /// Displays the change summary to the user.
    private func displayChangeSummary(_ summary: ChangeSummary) {
        noora.passthrough("\n📋 Change Summary:\n")

        if !summary.added.isEmpty {
            noora.passthrough("Added (\(summary.added.count)):\n", tab: 1)
            for path in summary.added.prefix(10) {
                noora.passthrough("+ \(path.pathString)\n", tab: 2)
            }
            if summary.added.count > 10 {
                noora.passthrough("... and \(summary.added.count - 10) more\n", tab: 2)
            }
        }

        if !summary.modified.isEmpty {
            noora.passthrough("Modified (\(summary.modified.count)):\n", tab: 1)
            for path in summary.modified.prefix(10) {
                noora.passthrough("~ \(path.pathString)\n", tab: 2)
            }
            if summary.modified.count > 10 {
                noora.passthrough("... and \(summary.modified.count - 10) more\n", tab: 2)
            }
        }

        if !summary.deleted.isEmpty {
            noora.passthrough("Deleted (\(summary.deleted.count)):\n", tab: 1)
            for path in summary.deleted.prefix(10) {
                noora.passthrough("- \(path.pathString)\n", tab: 2)
            }
            if summary.deleted.count > 10 {
                noora.passthrough("... and \(summary.deleted.count - 10) more\n", tab: 2)
            }
        }

        noora.passthrough("\nTotal: \(summary.totalCount) file(s)\n\n", tab: 1)
    }

    /// Displays detected conflicts to the user.
    private func displayConflicts(_ conflicts: [ConflictInfo]) {
        noora.passthrough("⚠️ Conflicts detected:\n")
        for conflict in conflicts {
            noora.passthrough("- \(conflict.path.pathString): \(conflict.type.description)\n", tab: 1)
        }
        noora.passthrough("\n")
    }

    /// Resolves macros based on input type.
    ///
    /// - Parameters:
    ///   - inputs: The macro inputs (parsed from CLI or requiring interactive prompts)
    ///   - config: The template configuration containing macro definitions
    ///   - workspaceRoot: The transactional workspace root directory (used as working directory for path resolution)
    /// - Returns: Array of resolved macros
    /// - Throws: Validation errors for parsed macros
    private func resolveMacros(
        _ inputs: MacroInputs,
        config: Config,
        workspaceRoot: AbsolutePath
    ) throws -> [ResolvedMacro] {
        switch inputs {
        case let .parsed(parsedMacros):
            // Resolve parsed macros with workspace root as working directory
            // This ensures path-type macros are resolved relative to the transactional workspace
            let validator = ParsedMacroDefinitionValidator(
                config: config,
                workingDirectory: workspaceRoot,
                homeDirectory: homeDirectory
            )
            return try validator.validate(parsedMacros)
        case .interactive:
            let resolver = MacroResolver(
                config: config,
                workingDirectory: workspaceRoot,
                homeDirectory: homeDirectory,
                noora: noora
            )
            return resolver.resolve()
        }
    }
}
