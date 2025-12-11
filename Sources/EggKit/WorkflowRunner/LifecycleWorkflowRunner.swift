import FileSystem
import Foundation
import Noora
import Path
import ProcessRunning

/// Orchestrates the complete lifecycle workflow: pre_hatch → hatch → post_hatch.
///
/// LifecycleWorkflowRunner coordinates the three main phases of template generation:
/// 1. **pre_hatch**: Prepare environment, validate inputs, generate metadata
/// 2. **hatch**: Expand template with macro and step output substitution
/// 3. **post_hatch**: Format code, initialize git, install dependencies
///
/// The workflow runner ensures that outputs from earlier phases are available to later phases,
/// enabling complex multi-step template generation workflows.
///
/// This is the legacy (non-sandboxed) implementation that operates directly on the working directory.
/// For atomic all-or-nothing execution, use `SandboxedWorkflowRunner` instead.
///
/// Example:
/// ```swift
/// let runner = LifecycleWorkflowRunner(
///     processRunner: ProcessRunner(),
///     fileSystem: FileSystem(),
///     workingDirectory: try AbsolutePath(validating: "/tmp/work"),
///     homeDirectory: try AbsolutePath(validating: NSHomeDirectory())
/// )
///
/// try await runner.run(
///     config: config,
///     macros: resolvedMacros,
///     templateDirectory: templateDir
/// )
/// ```
struct LifecycleWorkflowRunner: WorkflowRunning {
    private let workingDirectory: AbsolutePath
    private let phaseRunner: PhaseRunner
    private let noora: any Noorable

    init(
        processRunner: any ProcessRunning,
        fileSystem: any FileSysteming,
        workingDirectory: AbsolutePath,
        homeDirectory: AbsolutePath,
        noora: some Noorable = Noora(),
        isInteractive: Bool = true,
        force: Bool = false
    ) {
        self.workingDirectory = workingDirectory
        self.noora = noora
        self.phaseRunner = PhaseRunner(
            processRunner: processRunner,
            fileSystem: fileSystem,
            homeDirectory: homeDirectory,
            noora: noora,
            isInteractive: isInteractive,
            force: force
        )
    }

    /// Executes the complete lifecycle workflow.
    ///
    /// - Parameters:
    ///   - config: Template configuration containing lifecycle steps and hatch configuration
    ///   - macros: Resolved macros to substitute throughout the workflow
    ///   - templateDirectory: Source directory containing the template files
    /// - Returns: The resolved absolute path of the output directory
    /// - Throws: `LifecycleStepError` if any step fails, or file system errors
    func run(
        config: Config,
        macros: [ResolvedMacro],
        templateDirectory: AbsolutePath
    ) async throws -> AbsolutePath {
        let outputs = StepOutputsStorage()

        // Phase 1: Execute pre_hatch
        if let preHatchSteps = config.preHatch {
            try await phaseRunner.executePreHatch(
                steps: preHatchSteps,
                macros: macros,
                outputs: outputs,
                workingDirectory: workingDirectory
            )
        }

        // Phase 2: Execute hatch (template expansion)
        let outputDirectory = try await phaseRunner.executeHatch(
            config: config,
            macros: macros,
            outputs: outputs,
            templateDirectory: templateDirectory,
            workingDirectory: workingDirectory
        )

        noora.passthrough("✅ Template hatched successfully at \(outputDirectory.pathString)\n", tab: 1)

        // Phase 3: Execute post_hatch
        if let postHatchSteps = config.postHatch {
            try await phaseRunner.executePostHatch(
                steps: postHatchSteps,
                macros: macros,
                outputs: outputs,
                workingDirectory: workingDirectory
            )
        }

        return outputDirectory
    }
}
