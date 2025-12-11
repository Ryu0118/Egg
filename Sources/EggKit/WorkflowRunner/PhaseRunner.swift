import FileSystem
import Foundation
import Noora
import Path
import ProcessRunning

/// Executes individual workflow phases (pre_hatch, hatch, post_hatch).
///
/// PhaseRunner encapsulates the common logic for executing each phase of the workflow,
/// allowing both `LifecycleWorkflowRunner` and `SandboxedWorkflowRunner` to share
/// the same implementation while differing only in their orchestration strategy.
///
/// Example:
/// ```swift
/// let phaseRunner = PhaseRunner(
///     processRunner: ProcessRunner(),
///     fileSystem: FileSystem(),
///     homeDirectory: homeDir,
///     noora: Noora(),
///     isInteractive: true,
///     force: false
/// )
///
/// try await phaseRunner.executePreHatch(
///     steps: config.preHatch,
///     macros: macros,
///     outputs: outputs,
///     workingDirectory: workDir
/// )
/// ```
struct PhaseRunner {
    private let processRunner: any ProcessRunning
    private let fileSystem: any FileSysteming
    private let homeDirectory: AbsolutePath
    private let noora: any Noorable
    private let isInteractive: Bool
    private let force: Bool

    init(
        processRunner: any ProcessRunning,
        fileSystem: any FileSysteming,
        homeDirectory: AbsolutePath,
        noora: any Noorable,
        isInteractive: Bool,
        force: Bool
    ) {
        self.processRunner = processRunner
        self.fileSystem = fileSystem
        self.homeDirectory = homeDirectory
        self.noora = noora
        self.isInteractive = isInteractive
        self.force = force
    }

    /// Executes the pre_hatch lifecycle phase.
    ///
    /// Pre-hatch steps typically prepare the environment, validate inputs,
    /// or generate metadata that will be used during template expansion.
    ///
    /// - Parameters:
    ///   - steps: Pre-hatch lifecycle steps to execute
    ///   - macros: Resolved macros for variable substitution
    ///   - outputs: Storage for step outputs
    ///   - workingDirectory: Directory where steps execute
    ///   - additionalEnvironment: Extra environment variables for step execution
    ///   - executionEnvironment: Execution environment (normal or sandboxed)
    func executePreHatch(
        steps: [Config.LifecycleStep],
        macros: [ResolvedMacro],
        outputs: StepOutputsStorage,
        workingDirectory: AbsolutePath,
        additionalEnvironment: [String: String] = [:],
        executionEnvironment: ExecutionEnvironment = .normal
    ) async throws {
        noora.passthrough("🥚 Pre-hatch script executing...\n")

        let stepRunner = LifecycleStepRunner(
            processRunner: processRunner,
            workingDirectory: workingDirectory,
            noora: noora,
            additionalEnvironment: additionalEnvironment,
            executionEnvironment: executionEnvironment
        )

        _ = try await stepRunner.execute(
            .preHatch,
            steps: steps,
            substituting: macros,
            merging: outputs
        )
    }

    /// Executes the hatch phase (template expansion).
    ///
    /// Hatch phase expands the template directory to the output directory,
    /// performing macro substitution, step output substitution, and applying exclusion rules.
    ///
    /// - Parameters:
    ///   - config: Template configuration
    ///   - macros: Resolved macros for substitution
    ///   - outputs: Step outputs from pre_hatch phase
    ///   - templateDirectory: Source directory containing template files
    ///   - workingDirectory: Base directory for resolving output path
    ///   - pathValidator: Optional closure to validate the output path (e.g., sandbox boundary check)
    /// - Returns: The resolved absolute path of the output directory
    func executeHatch(
        config: Config,
        macros: [ResolvedMacro],
        outputs: StepOutputsStorage,
        templateDirectory: AbsolutePath,
        workingDirectory: AbsolutePath,
        pathValidator: ((AbsolutePath) async throws -> Void)? = nil
    ) async throws -> AbsolutePath {
        noora.passthrough("🐣 Hatching \(config.name)...\n")

        // Resolve macros in the output path first
        let resolver = VariableResolver(macros: macros, outputs: outputs)
        let resolvedOutput = try await resolver.resolve(config.hatch.output)

        let outputDirectory = try resolveToAbsolutePath(
            resolvedOutput,
            workingDirectory: workingDirectory,
            homeDirectory: homeDirectory
        )

        // Optional path validation (used by sandbox to ensure path is within bounds)
        if let validator = pathValidator {
            try await validator(outputDirectory)
        }

        // Safety check: output cannot be same as template
        if outputDirectory == templateDirectory {
            throw LifecycleStepError.invalidOutputDirectory(
                "Output directory cannot be the same as template directory: \(outputDirectory.pathString)"
            )
        }

        let expander = TemplateExpander(
            fileSystem: fileSystem,
            templateDirectory: templateDirectory,
            outputDirectory: outputDirectory,
            noora: noora,
            isInteractive: isInteractive,
            force: force
        )

        try await expander.expand(
            substituting: macros,
            with: outputs,
            excluding: config.hatch.exclude
        )

        return outputDirectory
    }

    /// Executes the post_hatch lifecycle phase.
    ///
    /// Post-hatch steps typically perform finalization tasks such as code formatting,
    /// git initialization, dependency installation, or running initial builds.
    ///
    /// - Parameters:
    ///   - steps: Post-hatch lifecycle steps to execute
    ///   - macros: Resolved macros for variable substitution
    ///   - outputs: Step outputs from pre_hatch and hatch phases
    ///   - workingDirectory: Directory where steps execute
    ///   - additionalEnvironment: Extra environment variables for step execution
    ///   - executionEnvironment: Execution environment (normal or sandboxed)
    func executePostHatch(
        steps: [Config.LifecycleStep],
        macros: [ResolvedMacro],
        outputs: StepOutputsStorage,
        workingDirectory: AbsolutePath,
        additionalEnvironment: [String: String] = [:],
        executionEnvironment: ExecutionEnvironment = .normal
    ) async throws {
        noora.passthrough("🐥 Post-hatch script executing...\n")

        let stepRunner = LifecycleStepRunner(
            processRunner: processRunner,
            workingDirectory: workingDirectory,
            noora: noora,
            additionalEnvironment: additionalEnvironment,
            executionEnvironment: executionEnvironment
        )

        _ = try await stepRunner.execute(
            .postHatch,
            steps: steps,
            substituting: macros,
            merging: outputs
        )
    }
}
