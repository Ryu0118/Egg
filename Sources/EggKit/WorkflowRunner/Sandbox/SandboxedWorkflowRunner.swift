import FileSystem
import Foundation
import Noora
import Path
import ProcessRunning

/// Orchestrates the complete lifecycle workflow with atomic all-or-nothing execution.
///
/// SandboxedWorkflowRunner executes all phases in a sandbox (APFS clone of working directory),
/// then applies only the changed files to the real working directory on success.
/// This provides:
/// - **Atomic execution**: Either all changes apply or none do
/// - **Safety**: Failed runs don't leave partial changes
/// - **Conflict detection**: Warns about concurrent modifications
/// - **User confirmation**: Shows change summary before applying (unless `force=true`)
///
/// Example:
/// ```swift
/// let runner = SandboxedWorkflowRunner(
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
struct SandboxedWorkflowRunner: WorkflowRunning {
    private let processRunner: any ProcessRunning
    private let fileSystem: any FileSysteming
    private let workingDirectory: AbsolutePath
    private let noora: any Noorable
    private let isInteractive: Bool
    private let force: Bool
    private let phaseRunner: PhaseRunner
    private let sandboxWatcher: any DirectoryWatching
    private let workingDirectoryWatcher: any DirectoryWatching

    init(
        processRunner: any ProcessRunning,
        fileSystem: any FileSysteming,
        workingDirectory: AbsolutePath,
        homeDirectory: AbsolutePath,
        noora: some Noorable = Noora(),
        isInteractive: Bool = true,
        force: Bool = false,
        sandboxWatcher: some DirectoryWatching = FSEventsDirectoryWatcher(),
        workingDirectoryWatcher: some DirectoryWatching = FSEventsDirectoryWatcher()
    ) {
        self.processRunner = processRunner
        self.fileSystem = fileSystem
        self.workingDirectory = workingDirectory
        self.noora = noora
        self.isInteractive = isInteractive
        self.force = force
        self.phaseRunner = PhaseRunner(
            processRunner: processRunner,
            fileSystem: fileSystem,
            homeDirectory: homeDirectory,
            noora: noora,
            isInteractive: isInteractive,
            force: force
        )
        self.sandboxWatcher = sandboxWatcher
        self.workingDirectoryWatcher = workingDirectoryWatcher
    }

    /// Executes the complete lifecycle workflow in a sandbox.
    ///
    /// - Parameters:
    ///   - config: Template configuration containing lifecycle steps and hatch configuration
    ///   - macros: Resolved macros to substitute throughout the workflow
    ///   - templateDirectory: Source directory containing the template files
    /// - Returns: The resolved absolute path of the output directory (in the real working directory)
    /// - Throws: `SandboxContext.Error` for sandbox-related failures, or other errors from phases
    func run(
        config: Config,
        macros: [ResolvedMacro],
        templateDirectory: AbsolutePath
    ) async throws -> AbsolutePath {
        // Step 1: Create sandbox (APFS clone of working directory)
        noora.passthrough("🔒 Creating sandbox...\n")
        let sandbox = try await SandboxContext.create(
            cloning: workingDirectory,
            fileSystem: fileSystem,
            sandboxWatcher: sandboxWatcher,
            workingDirectoryWatcher: workingDirectoryWatcher,
            processRunner: processRunner
        )

        // Ensure sandbox is discarded on any failure
        do {
            let outputs = StepOutputsStorage()

            // Step 2: Execute pre_hatch phase in sandbox (with OS-level sandboxing)
            let executionEnvironment = ExecutionEnvironment.sandboxed(
                root: sandbox.root,
                originalWorkingDirectory: workingDirectory
            )

            if let preHatchSteps = config.preHatch {
                try await phaseRunner.executePreHatch(
                    steps: preHatchSteps,
                    macros: macros,
                    outputs: outputs,
                    workingDirectory: sandbox.root,
                    executionEnvironment: executionEnvironment
                )
            }

            // Step 4: Execute hatch phase (template expansion) in sandbox
            let sandboxOutputDirectory = try await phaseRunner.executeHatch(
                config: config,
                macros: macros,
                outputs: outputs,
                templateDirectory: templateDirectory,
                workingDirectory: sandbox.root,
                pathValidator: { path in
                    try await sandbox.validatePath(path)
                }
            )

            noora.passthrough("✅ Template hatched successfully in sandbox.\n", tab: 1)

            // Calculate relative path for later use
            let resolvedOutputPath = try computeRelativePath(
                outputDirectory: sandboxOutputDirectory,
                sandboxRoot: sandbox.root
            )

            // Step 5: Execute post_hatch phase in sandbox (with OS-level sandboxing)
            if let postHatchSteps = config.postHatch {
                try await phaseRunner.executePostHatch(
                    steps: postHatchSteps,
                    macros: macros,
                    outputs: outputs,
                    workingDirectory: sandbox.root,
                    executionEnvironment: executionEnvironment
                )
            }

            // Step 6: Compute changes and handle conflicts
            let changeSummary = try await sandbox.computeChangeSummary()

            if changeSummary.isEmpty {
                noora.passthrough("ℹ️ No changes to apply.\n")
                await sandbox.discard()
                return workingDirectory.appending(resolvedOutputPath)
            }

            // Step 7: Display change summary
            displayChangeSummary(changeSummary)

            // Step 8: Handle confirmation based on mode
            try await confirmChanges(sandbox: sandbox)

            // Step 10: Apply changes to working directory
            noora.passthrough("📦 Applying changes...\n")
            let overriddenConflicts = try await sandbox.applyChanges(changeSummary, force: force)

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
            // Ensure sandbox is always discarded on error
            await sandbox.discard()
            throw error
        }
    }

    // MARK: - Private Helper Methods

    /// Computes the relative path from sandbox root to output directory.
    ///
    /// - Parameters:
    ///   - outputDirectory: The absolute output path within sandbox
    ///   - sandboxRoot: The sandbox root path
    /// - Returns: The relative path from sandbox root
    private func computeRelativePath(
        outputDirectory: AbsolutePath,
        sandboxRoot: AbsolutePath
    ) throws -> RelativePath {
        // If output is the sandbox root itself (output: "."), return "." as the relative path
        if outputDirectory == sandboxRoot {
            return try RelativePath(validating: ".")
        }

        // Remove the sandbox root prefix to get the relative path
        let pathString = outputDirectory.pathString
        let rootPrefix = sandboxRoot.pathString + "/"
        guard pathString.hasPrefix(rootPrefix) else {
            throw LifecycleStepError.invalidOutputDirectory(
                "Output path is not within sandbox: \(pathString)"
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
    private func confirmChanges(sandbox: SandboxContext) async throws {
        guard !force else { return }

        let conflicts = try await sandbox.detectConflicts()

        if !conflicts.isEmpty {
            displayConflicts(conflicts)
        }

        if isInteractive {
            let confirmed = noora.yesOrNoChoicePrompt(
                title: "Apply Changes",
                question: "Do you want to apply these changes to the working directory?"
            )
            guard confirmed else {
                noora.passthrough("❌ Changes discarded by user.\n")
                await sandbox.discard()
                throw SandboxContext.Error.userAborted
            }
        } else if !conflicts.isEmpty {
            await sandbox.discard()
            throw SandboxContext.Error.conflictingFiles(conflicts)
        }
    }

    // MARK: - Private Display Methods

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
}
