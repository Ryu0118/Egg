import FileSystem
import Foundation
import Noora
import Path
import ProcessRunning

/// Orchestrates the complete lifecycle workflow with atomic all-or-nothing execution.
///
/// StagingWorkflowRunner executes all phases in a staging workspace (APFS clone of working directory),
/// then applies only the changed files to the real working directory on success.
/// This provides:
/// - **Atomic execution**: Either all changes apply or none do
/// - **Safety**: Failed runs don't leave partial changes
/// - **Conflict detection**: Warns about concurrent modifications
/// - **User confirmation**: Shows change summary before applying (unless `force=true`)
///
/// Example:
/// ```swift
/// let runner = StagingWorkflowRunner(
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
struct StagingWorkflowRunner: WorkflowRunning {
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

    /// Executes the complete lifecycle workflow in a staging workspace.
    ///
    /// - Parameters:
    ///   - config: Template configuration containing lifecycle steps and hatch configuration
    ///   - macroInputs: Macro inputs to be resolved (either already resolved or pending interactive prompts)
    ///   - templateDirectory: Source directory containing the template files
    /// - Returns: The resolved absolute path of the output directory (in the real working directory)
    /// - Throws: `StagingContext.Error` for staging workspace-related failures, or other errors from phases
    func run(
        config: Config,
        macroInputs: MacroInputs,
        templateDirectory: AbsolutePath
    ) async throws -> AbsolutePath {
        // Step 1: Start staging workspace creation in parallel with macro collection
        noora.passthrough("🔒 Creating staging workspace...\n")

        // Copy fileSystem to a local variable to satisfy sending requirement
        // FileSystem is thread-safe but not marked Sendable
        nonisolated(unsafe) let fs = fileSystem

        nonisolated(unsafe) let nra = noora

        let workspaceTask = Self.createWorkspaceTask(
            workingDirectory: workingDirectory,
            homeDirectory: homeDirectory,
            fileSystem: fs,
            workspaceWatcher: workspaceWatcher,
            workingDirectoryWatcher: workingDirectoryWatcher,
            processRunner: processRunner,
            noora: nra
        )

        // Step 2: Collect macro values (runs in parallel with workspace creation)
        let collectedMacroValues = collectMacroValues(macroInputs, config: config)

        // Wait for workspace creation to complete
        let staging = try await workspaceTask.value

        // Register cleanup handler for SIGINT/SIGTERM (Control+C)
        let cleanupHandlerId = await StagingCleanupRegistry.shared.register {
            await staging.discard()
        }

        // Ensure cleanup handler is unregistered when we're done
        defer {
            Task {
                await StagingCleanupRegistry.shared.unregister(cleanupHandlerId)
            }
        }

        // Ensure staging workspace is discarded on any failure
        do {
            // Step 4: Resolve macros with workspace root as working directory
            // This is critical for path-type macros to resolve correctly
            let macros = try finalizeMacros(collectedMacroValues, config: config, workspaceRoot: staging.root)

            let outputs = StepOutputsStorage()

            // Step 2: Execute pre_hatch phase in staging workspace (with OS-level sandboxing)
            let executionEnvironment = ExecutionEnvironment.staging(
                root: staging.root,
                originalWorkingDirectory: workingDirectory
            )

            if let preHatchSteps = config.preHatch {
                try await phaseRunner.executePreHatch(
                    steps: preHatchSteps,
                    macros: macros,
                    outputs: outputs,
                    workingDirectory: staging.root,
                    additionalEnvironment: ["EGG_STAGING_ROOT": staging.root.pathString],
                    executionEnvironment: executionEnvironment
                )
            }

            // Step 4: Execute hatch phase (template expansion) in staging workspace
            let workspaceOutputDirectory = try await phaseRunner.executeHatch(
                config: config,
                macros: macros,
                outputs: outputs,
                templateDirectory: templateDirectory,
                workingDirectory: staging.root,
                pathValidator: { path in
                    try await staging.validatePath(path)
                }
            )

            noora.passthrough("✅ Template hatched successfully in staging workspace.\n", tab: 1)
            // Calculate relative path for later use
            let resolvedOutputPath = try computeRelativePath(
                outputDirectory: workspaceOutputDirectory,
                workspaceRoot: staging.root
            )

            // Step 5: Execute post_hatch phase in staging workspace (with OS-level sandboxing)
            if let postHatchSteps = config.postHatch {
                try await phaseRunner.executePostHatch(
                    steps: postHatchSteps,
                    macros: macros,
                    outputs: outputs,
                    workingDirectory: staging.root,
                    executionEnvironment: executionEnvironment
                )
            }

            // Step 6: Compute changes and handle conflicts
            let changeSummary = try await staging.computeChangeSummary()

            if changeSummary.isEmpty {
                noora.passthrough("ℹ️ No changes to apply.\n")
                await staging.discard()
                return workingDirectory.appending(resolvedOutputPath)
            }

            // Step 7: Display change summary
            displayChangeSummary(changeSummary)

            // Step 8: Handle confirmation based on mode
            try await confirmChanges(staging: staging)

            // Step 10: Apply changes to working directory
            noora.passthrough("📦 Applying changes...\n")
            let overriddenConflicts = try await staging.applyChanges(changeSummary, force: force)

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
            // Ensure staging workspace is always discarded on error
            await staging.discard()
            throw error
        }
    }

    /// Computes the relative path from workspace root to output directory.
    ///
    /// - Parameters:
    ///   - outputDirectory: The absolute output path within staging workspace
    ///   - workspaceRoot: The staging workspace root path
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
                "Output path is not within staging workspace: \(pathString)"
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
    private func confirmChanges(staging: StagingContext) async throws {
        guard !force else { return }

        let conflicts = try await staging.detectConflicts()

        if !conflicts.isEmpty {
            displayConflicts(conflicts)
        }

        if isInteractive {
            let confirmed = noora.yesOrNoChoicePrompt(
                title: "Apply Changes (staging workspace → current directory)",
                question: "Apply to \(staging.originalWorkingDirectory.pathString)?"
            )
            guard confirmed else {
                noora.passthrough("❌ Changes discarded by user.\n")
                await staging.discard()
                throw StagingContext.Error.userAborted
            }
        } else if !conflicts.isEmpty {
            await staging.discard()
            throw StagingContext.Error.conflictingFiles(conflicts)
        }
    }

    /// Displays the change summary to the user.
    private func displayChangeSummary(_ summary: ChangeSummary) {
        noora.passthrough("\n📋 Change Summary:\n")

        if !summary.added.isEmpty {
            noora.passthrough("Added (\(summary.added.count)):\n", tab: 1)
            for path in summary.added {
                noora.passthrough("+ \(path.pathString)\n", tab: 2)
            }
        }

        if !summary.modified.isEmpty {
            noora.passthrough("Modified (\(summary.modified.count)):\n", tab: 1)
            for path in summary.modified {
                noora.passthrough("~ \(path.pathString)\n", tab: 2)
            }
        }

        if !summary.deleted.isEmpty {
            noora.passthrough("Deleted (\(summary.deleted.count)):\n", tab: 1)
            for path in summary.deleted {
                noora.passthrough("- \(path.pathString)\n", tab: 2)
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

    /// Creates a detached task for workspace creation to enable parallel execution.
    ///
    /// This helper method isolates the non-Sendable FileSysteming type by using
    /// `sending` parameters and `nonisolated(unsafe)` to safely pass it to the task.
    ///
    /// - Returns: A task that creates the staging workspace
    private nonisolated static func createWorkspaceTask(
        workingDirectory: AbsolutePath,
        homeDirectory: AbsolutePath,
        fileSystem: sending any FileSysteming,
        workspaceWatcher: any DirectoryWatching,
        workingDirectoryWatcher: any DirectoryWatching,
        processRunner: any ProcessRunning,
        noora: sending any Noorable
    ) -> Task<StagingContext, any Error> {
        // Use nonisolated(unsafe) to safely capture non-Sendable types in the task
        // FileSystem and Noora are actually thread-safe but not marked Sendable
        nonisolated(unsafe) let fs = fileSystem
        nonisolated(unsafe) let nra = noora

        return Task {
            try await StagingContext.create(
                cloning: workingDirectory,
                homeDirectory: homeDirectory,
                fileSystem: fs,
                workspaceWatcher: workspaceWatcher,
                workingDirectoryWatcher: workingDirectoryWatcher,
                processRunner: processRunner,
                noora: nra
            )
        }
    }

    /// Intermediate representation for collected macro values before workspace-relative path resolution.
    private enum CollectedMacroValues {
        /// Pre-validated parsed macros from CLI arguments (need workspace-relative path resolution)
        case parsed([ParsedMacroDefinition])
        /// Interactively collected macros using original working directory (need workspace-relative path re-resolution)
        case interactive([ResolvedMacro])
    }

    /// Collects macro values from user input or CLI arguments.
    ///
    /// For interactive mode, this prompts the user and collects values while workspace creation
    /// proceeds in parallel. Path validation uses the original working directory (which has the
    /// same structure as the workspace clone).
    ///
    /// - Parameters:
    ///   - inputs: The macro inputs (parsed from CLI or requiring interactive prompts)
    ///   - config: The template configuration containing macro definitions
    /// - Returns: Collected macro values ready for workspace-relative finalization
    private func collectMacroValues(_ inputs: MacroInputs, config: Config) -> CollectedMacroValues {
        switch inputs {
        case let .parsed(parsedMacros):
            // Pass through parsed macros for later validation
            return .parsed(parsedMacros)
        case .interactive:
            // Collect user input using original working directory for path validation
            // Since workspace is an APFS clone, relative paths resolve the same
            let resolver = MacroResolver(
                config: config,
                workingDirectory: workingDirectory,
                homeDirectory: homeDirectory,
                noora: noora
            )
            return .interactive(resolver.resolve())
        }
    }

    /// Finalizes macro resolution with workspace-relative paths.
    ///
    /// For parsed macros, validates and resolves paths relative to workspace root.
    /// For interactive macros, re-resolves path values relative to workspace root.
    ///
    /// - Parameters:
    ///   - collected: The collected macro values from `collectMacroValues`
    ///   - config: The template configuration containing macro definitions
    ///   - workspaceRoot: The staging workspace root directory
    /// - Returns: Array of resolved macros with workspace-relative paths
    /// - Throws: Validation errors for parsed macros
    private func finalizeMacros(
        _ collected: CollectedMacroValues,
        config: Config,
        workspaceRoot: AbsolutePath
    ) throws -> [ResolvedMacro] {
        switch collected {
        case let .parsed(parsedMacros):
            // Validate and resolve parsed macros with workspace root
            let validator = ParsedMacroDefinitionValidator(
                config: config,
                workingDirectory: workspaceRoot,
                homeDirectory: homeDirectory
            )
            return try validator.validate(parsedMacros)
        case let .interactive(resolvedMacros):
            // Re-resolve path macros relative to workspace root
            // Since workspace is an APFS clone, paths resolve to equivalent locations
            return resolvedMacros.map { macro in
                guard case let .path(originalPath) = macro.value else {
                    return macro
                }
                // Compute relative path from original working directory
                let relativePath = originalPath.relative(to: workingDirectory)
                // Re-resolve relative to workspace root
                let workspacePath = workspaceRoot.appending(relativePath)
                return ResolvedMacro(
                    name: macro.name,
                    description: macro.description,
                    value: .path(workspacePath)
                )
            }
        }
    }
}
