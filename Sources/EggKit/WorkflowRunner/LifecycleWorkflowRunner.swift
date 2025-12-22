import FileManagerProtocol
import Foundation
import Noora
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
/// This is the legacy (non-staging) implementation that operates directly on the working directory.
/// For atomic all-or-nothing execution, use `StagingWorkflowRunner` instead.
///
/// Example:
/// ```swift
/// let runner = LifecycleWorkflowRunner(
///     processRunner: ProcessRunner(),
///     fileManager: FileManager.default,
///     workingDirectory: URL(filePath: "/tmp/work"),
///     homeDirectory: URL(filePath: NSHomeDirectory())
/// )
///
/// try await runner.run(
///     config: config,
///     macroInputs: .interactive,
///     templateDirectory: templateDir
/// )
/// ```
struct LifecycleWorkflowRunner: WorkflowRunning {
    private let workingDirectory: URL
    private let homeDirectory: URL
    private let phaseRunner: PhaseRunner
    private let noora: any Noorable
    private let sandboxDisabled: Bool

    init(
        processRunner: any ProcessRunning,
        fileManager: some FileManagerProtocol,
        workingDirectory: URL,
        homeDirectory: URL,
        noora: some Noorable = Noora(),
        isInteractive: Bool = true,
        overrideConflicts: Bool = false,
        sandboxDisabled: Bool = true,
        applyChanges: Bool = false
    ) {
        // Note: applyChanges is unused in direct mode as there's no confirmation step
        _ = applyChanges
        self.workingDirectory = workingDirectory
        self.homeDirectory = homeDirectory
        self.noora = noora
        self.sandboxDisabled = sandboxDisabled
        phaseRunner = PhaseRunner(
            processRunner: processRunner,
            fileManager: fileManager,
            homeDirectory: homeDirectory,
            noora: noora,
            isInteractive: isInteractive,
            override: overrideConflicts
        )
    }

    /// Executes the complete lifecycle workflow.
    ///
    /// - Parameters:
    ///   - config: Template configuration containing lifecycle steps and hatch configuration
    ///   - macroInputs: Macro inputs to be resolved (either already resolved or pending interactive prompts)
    ///   - templateDirectory: Source directory containing the template files
    /// - Returns: The resolved absolute path of the output directory
    /// - Throws: `LifecycleStepError` if any step fails, or file system errors
    func run(
        config: Config,
        macroInputs: MacroInputs,
        templateDirectory: URL
    ) async throws -> URL {
        // Resolve macros (for non-staging execution, use real working directory)
        let macros = try resolveMacros(macroInputs, config: config)

        let outputs = StepOutputsStorage()

        let executionEnvironment: ExecutionEnvironment =
            sandboxDisabled ? .unsandboxed : .sandboxed(.workingDirectory(workingDirectory))

        // Common environment variables for all phases
        let commonEnvironment = ["EGG_WORKING_DIRECTORY": workingDirectory.path(percentEncoded: false)]

        // Execute pre_hatch
        if let preHatchSteps = config.preHatch {
            try await phaseRunner.executePreHatch(
                steps: preHatchSteps,
                macros: macros,
                outputs: outputs,
                workingDirectory: workingDirectory,
                additionalEnvironment: commonEnvironment,
                executionEnvironment: executionEnvironment
            )
        }

        // Execute hatch (template expansion)
        let outputDirectory = try await phaseRunner.executeHatch(
            config: config,
            macros: macros,
            outputs: outputs,
            templateDirectory: templateDirectory,
            workingDirectory: workingDirectory
        )

        // Execute post_hatch
        if let postHatchSteps = config.postHatch {
            try await phaseRunner.executePostHatch(
                steps: postHatchSteps,
                macros: macros,
                outputs: outputs,
                workingDirectory: workingDirectory,
                additionalEnvironment: commonEnvironment,
                executionEnvironment: executionEnvironment
            )
        }

        return outputDirectory
    }

    /// Resolves macros based on input type.
    ///
    /// - Parameters:
    ///   - inputs: The macro inputs (parsed from CLI or requiring interactive prompts)
    ///   - config: The template configuration containing macro definitions
    /// - Returns: Array of resolved macros
    /// - Throws: Validation errors for parsed macros
    private func resolveMacros(_ inputs: MacroInputs, config: Config) throws -> [ResolvedMacro] {
        switch inputs {
        case let .parsed(parsedMacros):
            // Resolve parsed macros with real working directory
            // (non-staging execution uses the actual working directory)
            let validator = ParsedMacroDefinitionValidator(
                config: config,
                workingDirectory: workingDirectory,
                homeDirectory: homeDirectory
            )
            return try validator.validate(parsedMacros)
        case .interactive:
            let resolver = MacroResolver(
                config: config,
                workingDirectory: workingDirectory,
                homeDirectory: homeDirectory,
                noora: noora
            )
            return resolver.resolve()
        }
    }
}
