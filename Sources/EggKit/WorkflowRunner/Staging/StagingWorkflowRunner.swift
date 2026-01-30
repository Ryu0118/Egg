import FileManagerProtocol
import Foundation
import Noora
import ProcessRunning

/// Orchestrates the complete lifecycle workflow with atomic all-or-nothing execution.
///
/// StagingWorkflowRunner executes all phases in a staging workspace (APFS clone of working directory),
/// then applies only the changed files to the real working directory on success.
/// This provides:
/// - **Atomic execution**: Either all changes apply or none do
/// - **Safety**: Failed runs don't leave partial changes
/// - **Conflict detection**: Warns about concurrent modifications
/// - **User confirmation**: Shows change summary before applying (unless `override=true`)
///
/// Example:
/// ```swift
/// let runner = StagingWorkflowRunner(
///     processRunner: ProcessRunner(),
///     fileManager: FileManager.default,
///     workingDirectory: URL(filePath: "/tmp/project"),
///     homeDirectory: URL(filePath: NSHomeDirectory()),
///     noora: Noora(),
///     isInteractive: true,
///     override: false
/// )
///
/// let outputPath = try await runner.run(
///     config: config,
///     macros: resolvedMacros,
///     templateDirectory: templateDir
/// )
/// ```
/// Determines how apply-changes confirmation is handled.
enum ApplyConfirmationMode {
    /// Always skip confirmation and apply immediately, overriding any conflicts.
    case alwaysApply
    /// Skip confirmation prompt but warn about conflicts.
    case autoConfirm
    /// Show yes/no prompt before applying changes.
    case prompt
}

struct StagingWorkflowRunner: WorkflowRunning {
    private let processRunner: any ProcessRunning
    private let fileManager: any FileManagerProtocol
    private let workingDirectory: URL
    private let homeDirectory: URL
    private let noora: any Noorable
    private let isInteractive: Bool
    private let overrideConflicts: Bool
    private let sandboxDisabled: Bool
    private let confirmationMode: ApplyConfirmationMode
    private let phaseRunner: PhaseRunner
    private let workspaceWatcher: any DirectoryWatching
    private let workingDirectoryWatcher: any DirectoryWatching
    private let stagingRoot: URL?

    init(
        processRunner: any ProcessRunning,
        fileManager: some FileManagerProtocol,
        workingDirectory: URL,
        homeDirectory: URL,
        noora: some Noorable = Noora(),
        isInteractive: Bool = true,
        overrideConflicts: Bool = false,
        sandboxDisabled: Bool = false,
        applyChanges: Bool = false,
        workspaceWatcher: some DirectoryWatching = FSEventsDirectoryWatcher(),
        workingDirectoryWatcher: some DirectoryWatching = FSEventsDirectoryWatcher(),
        stagingRoot: URL? = nil
    ) {
        self.processRunner = processRunner
        self.fileManager = fileManager
        self.workingDirectory = workingDirectory
        self.homeDirectory = homeDirectory
        self.noora = noora
        self.isInteractive = isInteractive
        self.overrideConflicts = overrideConflicts
        self.sandboxDisabled = sandboxDisabled
        self.stagingRoot = stagingRoot
        // Determine confirmation mode from flags
        if overrideConflicts {
            confirmationMode = .alwaysApply
        } else if applyChanges {
            confirmationMode = .autoConfirm
        } else {
            confirmationMode = .prompt
        }
        phaseRunner = PhaseRunner(
            processRunner: processRunner,
            fileManager: fileManager,
            homeDirectory: homeDirectory,
            noora: noora,
            isInteractive: isInteractive,
            override: overrideConflicts
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
        templateDirectory: URL
    ) async throws -> URL {
        // Step 1: Create staging workspace
        // Use stagingRoot if specified, otherwise fall back to workingDirectory
        let directoryToClone = stagingRoot ?? workingDirectory
        noora.passthrough("🔒 Creating staging workspace...\n")

        let staging = try await StagingContext.create(
            cloning: directoryToClone,
            fileManager: fileManager,
            workspaceWatcher: workspaceWatcher,
            workingDirectoryWatcher: workingDirectoryWatcher,
            processRunner: processRunner,
            noora: noora
        )

        // Register cleanup handler for SIGINT/SIGTERM (Control+C) IMMEDIATELY after staging creation
        // This must happen BEFORE collectMacroValues() which may block on user input
        let cleanupHandlerId = await StagingCleanupRegistry.shared.register {
            await staging.discard()
        }

        // Ensure cleanup handler is unregistered when we're done
        defer {
            Task {
                await StagingCleanupRegistry.shared.unregister(cleanupHandlerId)
            }
        }

        // Step 2: Collect macro values (may block on interactive user input)
        let collectedMacroValues = collectMacroValues(macroInputs, config: config)

        // Ensure staging workspace is discarded on any failure
        do {
            // Step 4: Resolve macros with workspace root as working directory
            // This is critical for path-type macros to resolve correctly
            let macros = try finalizeMacros(collectedMacroValues, config: config, workspaceRoot: staging.root)

            // Expand and validate sandbox.allowed_paths
            let sandboxResolver = SandboxAllowedPathsResolver(homeDirectory: homeDirectory, noora: noora)
            let expandedAllowedPaths = try await sandboxResolver.expandAllowedPaths(
                config.sandbox?.allowedPaths,
                macros: macros,
                workingDirectory: staging.root
            )

            // Track whether user confirmed extended sandbox permissions
            var sandboxPermissionConfirmed = false

            // If allowed_paths are specified and sandbox is enabled, handle permission
            if !expandedAllowedPaths.isEmpty && !sandboxDisabled {
                if isInteractive {
                    // Prompt user for permission in interactive mode
                    sandboxPermissionConfirmed = sandboxResolver.confirmSandboxAllowedPaths(
                        expandedAllowedPaths.map { $0.path(percentEncoded: false) }
                    )
                    if !sandboxPermissionConfirmed {
                        noora.passthrough("⚠️ Continuing without extended sandbox permissions (sandbox-only mode).\n")
                    }
                } else {
                    // Non-interactive mode: reject with error
                    throw LifecycleStepError.sandboxPermissionRequired(
                        paths: expandedAllowedPaths.map { $0.path(percentEncoded: false) }
                    )
                }
            }

            let outputs = StepOutputsStorage()

            // Compute final allowed paths for sandbox configuration
            // Only include if user confirmed in interactive mode
            let finalAllowedPaths: [URL] = sandboxPermissionConfirmed ? expandedAllowedPaths : []

            // Step 2: Execute pre_hatch phase in staging workspace (with OS-level sandboxing)
            let executionEnvironment: ExecutionEnvironment =
                if sandboxDisabled {
                    .unsandboxed
                } else {
                    .sandboxed(.staging(
                        root: staging.root,
                        originalWorkingDirectory: workingDirectory,
                        allowedPaths: finalAllowedPaths
                    ))
                }

            // Common environment variables for all phases
            // In staging mode, EGG_WORKING_DIRECTORY points to the staging workspace
            // EGG_ORIGINAL_WORKING_DIRECTORY always points to the original working directory
            let commonEnvironment = [
                "EGG_WORKING_DIRECTORY": staging.root.path(percentEncoded: false),
                "EGG_ORIGINAL_WORKING_DIRECTORY": workingDirectory.path(percentEncoded: false),
            ]

            if let preHatchSteps = config.preHatch {
                try await phaseRunner.executePreHatch(
                    steps: preHatchSteps,
                    macros: macros,
                    outputs: outputs,
                    workingDirectory: staging.root,
                    additionalEnvironment: commonEnvironment,
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

            // Calculate relative path for later use
            let resolvedOutputPath: String
            do {
                resolvedOutputPath = try workspaceOutputDirectory.relativePathThrowing(from: staging.root)
            } catch is RelativePathError {
                throw LifecycleStepError.invalidOutputDirectory(
                    "Output path is not within staging workspace: \(workspaceOutputDirectory.normalizedPath)"
                )
            }

            // Step 5: Execute post_hatch phase in staging workspace (with OS-level sandboxing)
            if let postHatchSteps = config.postHatch {
                try await phaseRunner.executePostHatch(
                    steps: postHatchSteps,
                    macros: macros,
                    outputs: outputs,
                    workingDirectory: staging.root,
                    additionalEnvironment: commonEnvironment,
                    executionEnvironment: executionEnvironment
                )
            }

            // Step 6: Compute changes and handle conflicts
            let changeSummary = try await staging.computeChangeSummary()

            if changeSummary.isEmpty {
                noora.passthrough("ℹ️ No changes to apply.\n")
                await staging.discard()
                return workingDirectory.appending(path: resolvedOutputPath)
            }

            // Step 7: Display change summary
            displayChangeSummary(changeSummary)

            // Step 8: Handle confirmation based on mode
            // Returns true if user confirmed to override conflicts in interactive mode
            let userConfirmedOverride = try await confirmChanges(staging: staging)

            // Step 10: Apply changes to working directory
            noora.passthrough("📦 Applying changes...\n")
            // Use override if set via CLI flag, OR if user confirmed override in interactive mode
            let overriddenConflicts = try await staging.applyChanges(changeSummary, override: overrideConflicts || userConfirmedOverride)

            // Display warning for overridden conflicts (when override=true)
            if !overriddenConflicts.isEmpty {
                noora.passthrough("⚠️ Overwritten conflicting files:\n")
                for conflict in overriddenConflicts {
                    noora.passthrough("- \(conflict.pathString) (\(conflict.type.description))\n", tab: 1)
                }
            }

            noora.passthrough("✅ Changes applied successfully!\n")

            // Return path in real working directory
            return workingDirectory.appending(path: resolvedOutputPath)

        } catch {
            // Ensure staging workspace is always discarded on error
            await staging.discard()
            throw error
        }
    }

    /// Handles user confirmation before applying changes.
    ///
    /// Behavior based on `confirmationMode`:
    /// - `.alwaysApply`: Skip confirmation, apply immediately (--override flag)
    /// - `.autoConfirm`: Skip prompt, apply with warning if conflicts exist (--yes flag)
    /// - `.prompt`: Show yes/no prompt before applying (default)
    ///
    /// - Returns: True if there were conflicts that will be overridden, false otherwise
    @discardableResult
    private func confirmChanges(staging: StagingContext) async throws -> Bool {
        let conflicts = try await staging.detectConflicts()
        let hasConflicts = !conflicts.isEmpty

        if hasConflicts {
            displayConflicts(conflicts)
        }

        switch confirmationMode {
        case .alwaysApply:
            // --override: apply without any confirmation
            return false

        case .autoConfirm:
            // --yes: apply without prompt, but warn about conflicts
            if hasConflicts {
                noora.warning("Auto-confirming: overriding \(conflicts.count) conflicting file(s)")
            }
            return hasConflicts

        case .prompt:
            // Default: show yes/no prompt
            let confirmed =
                if hasConflicts {
                    noora.yesOrNoChoicePrompt(
                        title: "Apply Changes and Override Conflicts",
                        question: "Override conflicting files and apply to \(staging.originalWorkingDirectory.path(percentEncoded: false))?"
                    )
                } else {
                    noora.yesOrNoChoicePrompt(
                        title: "Apply Changes (staging workspace → current directory)",
                        question: "Apply to \(staging.originalWorkingDirectory.path(percentEncoded: false))?"
                    )
                }
            guard confirmed else {
                noora.passthrough("❌ Changes discarded by user.\n")
                await staging.discard()
                throw StagingContext.Error.userAborted
            }
            return hasConflicts
        }
    }

    /// Displays the change summary to the user.
    private func displayChangeSummary(_ summary: ChangeSummary) {
        noora.passthrough("\n📋 Change Summary:\n")

        if !summary.added.isEmpty {
            noora.passthrough("\(.success("Added")) (\(summary.added.count)):\n", tab: 1)
            for path in summary.added {
                noora.passthrough("\(.success("+")) \(path)\n", tab: 2)
            }
        }

        if !summary.modified.isEmpty {
            noora.passthrough("\(.accent("Modified")) (\(summary.modified.count)):\n", tab: 1)
            for path in summary.modified {
                noora.passthrough("\(.accent("~")) \(path)\n", tab: 2)
            }
        }

        if !summary.deleted.isEmpty {
            noora.passthrough("\(.danger("Deleted")) (\(summary.deleted.count)):\n", tab: 1)
            for path in summary.deleted {
                noora.passthrough("\(.danger("-")) \(path)\n", tab: 2)
            }
        }

        noora.passthrough("\nTotal: \(summary.totalCount) file(s)\n\n", tab: 1)
    }

    /// Displays detected conflicts to the user.
    private func displayConflicts(_ conflicts: [ConflictInfo]) {
        noora.passthrough("⚠️ Conflicts detected:\n")
        for conflict in conflicts {
            noora.passthrough("- \(conflict.pathString): \(conflict.type.description)\n", tab: 1)
        }
        noora.passthrough("\n")
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
        workspaceRoot: URL
    ) throws -> [ResolvedMacro] {
        // The directory that was cloned into the staging workspace
        let clonedDirectory = stagingRoot ?? workingDirectory

        switch collected {
        case let .parsed(parsedMacros):
            // Validate and resolve parsed macros with the original cloned directory first,
            // then remap path macros to the staging workspace
            let validator = ParsedMacroDefinitionValidator(
                config: config,
                workingDirectory: clonedDirectory,
                homeDirectory: homeDirectory
            )
            let resolvedMacros = try validator.validate(parsedMacros)
            // Remap path macros to staging workspace
            return remapPathMacros(resolvedMacros, from: clonedDirectory, to: workspaceRoot)
        case let .interactive(resolvedMacros):
            // Re-resolve path macros relative to workspace root
            // Since workspace is an APFS clone, paths resolve to equivalent locations
            return remapPathMacros(resolvedMacros, from: clonedDirectory, to: workspaceRoot)
        }
    }

    /// Remaps path-type macros from the original directory to the staging workspace.
    ///
    /// For each path macro, computes the relative path from the original directory,
    /// then resolves it relative to the workspace root.
    ///
    /// Paths that are outside the original directory (absolute paths pointing elsewhere)
    /// are preserved as-is without remapping.
    ///
    /// - Parameters:
    ///   - macros: The resolved macros to remap
    ///   - originalDirectory: The original directory (before staging)
    ///   - workspaceRoot: The staging workspace root
    /// - Returns: Macros with path values remapped to workspace
    private func remapPathMacros(
        _ macros: [ResolvedMacro],
        from originalDirectory: URL,
        to workspaceRoot: URL
    ) -> [ResolvedMacro] {
        macros.map { macro in
            guard case let .path(originalPath) = macro.value else {
                return macro
            }

            // Check if the path is within the original directory
            guard originalPath.isUnder(originalDirectory) else {
                // Path is outside the original directory (e.g., /usr/local/bin)
                // Keep it as-is without remapping
                return macro
            }

            // Compute relative path from original directory
            let relativePath = originalPath.relativePath(from: originalDirectory)
            // Re-resolve relative to workspace root
            let workspacePath = workspaceRoot.appending(path: relativePath)
            return ResolvedMacro(
                name: macro.name,
                description: macro.description,
                value: .path(workspacePath)
            )
        }
    }

}
