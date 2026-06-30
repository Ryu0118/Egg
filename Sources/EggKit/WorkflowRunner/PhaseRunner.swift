import FileManagerProtocol
import Foundation
import Noora
import ProcessRunning

/// Executes individual workflow phases (pre_hatch, hatch, post_hatch).
///
/// PhaseRunner encapsulates the common logic for executing each phase of the workflow,
/// allowing both `LifecycleWorkflowRunner` and `StagingWorkflowRunner` to share
/// the same implementation while differing only in their orchestration strategy.
///
/// Example:
/// ```swift
/// let phaseRunner = PhaseRunner(
///     processRunner: ProcessRunner(),
///     fileManager: FileManager.default,
///     homeDirectory: homeDir,
///     noora: Noora(),
///     isInteractive: true,
///     override: false
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
    private let fileManager: any FileManagerProtocol
    private let homeDirectory: URL
    private let noora: any Noorable
    private let isInteractive: Bool
    private let override: Bool
    private let processEnvironment: [String: String]
    private let builtInMacroDate: Date

    init(
        processRunner: any ProcessRunning,
        fileManager: some FileManagerProtocol,
        homeDirectory: URL,
        noora: some Noorable,
        isInteractive: Bool,
        override: Bool,
        processEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        builtInMacroDate: Date = Date(),
    ) {
        self.processRunner = processRunner
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory
        self.noora = noora
        self.isInteractive = isInteractive
        self.override = override
        self.processEnvironment = processEnvironment
        self.builtInMacroDate = builtInMacroDate
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
    ///   - executionEnvironment: Execution environment (normal or staging)
    func executePreHatch(
        steps: [Config.LifecycleStep],
        macros: [ResolvedMacro],
        outputs: StepOutputsStorage,
        workingDirectory: URL,
        additionalEnvironment: [String: String] = [:],
        executionEnvironment: ExecutionEnvironment = .unsandboxed,
    ) async throws {
        progress("🥚 Pre-hatch script executing...\n")

        let builtInContext = makeBuiltInMacroContext(
            workingDirectory: workingDirectory,
            additionalEnvironment: additionalEnvironment,
        )

        let stepRunner = LifecycleStepRunner(
            processRunner: processRunner,
            workingDirectory: workingDirectory,
            noora: noora,
            additionalEnvironment: additionalEnvironment,
            executionEnvironment: executionEnvironment,
            builtInMacroContext: builtInContext,
        )

        _ = try await stepRunner.execute(
            .preHatch,
            steps: steps,
            substituting: macros,
            merging: outputs,
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
    ///   - pathValidator: Optional closure to validate the output path (e.g., staging boundary check)
    /// - Returns: The resolved absolute path of the output directory
    func executeHatch(
        config: Config,
        macros: [ResolvedMacro],
        outputs: StepOutputsStorage,
        templateDirectory: URL,
        workingDirectory: URL,
        pathValidator: ((URL) async throws -> Void)? = nil,
    ) async throws -> URL {
        progress("🐣 Hatching \(config.name)...\n")

        // Resolve macros in the output path first
        let resolver = VariableResolver(
            macros: macros,
            outputs: outputs,
            builtInMacroContext: makeBuiltInMacroContext(workingDirectory: workingDirectory),
        )
        let resolvedOutput = try await resolver.resolve(config.hatch.output)

        let outputDirectory = try PathResolver.resolveToAbsoluteURL(
            resolvedOutput,
            workingDirectory: workingDirectory,
            homeDirectory: homeDirectory,
        )

        // Optional path validation (used by staging to ensure path is within bounds)
        if let validator = pathValidator {
            try await validator(outputDirectory)
        }

        // Safety check: output cannot be same as template
        if outputDirectory == templateDirectory {
            throw LifecycleStepError.invalidOutputDirectory(
                "Output directory cannot be the same as template directory: \(outputDirectory.path(percentEncoded: false))",
            )
        }

        let expander = TemplateExpander(
            fileManager: fileManager,
            templateDirectory: templateDirectory,
            outputDirectory: outputDirectory,
            builtInMacroContext: makeBuiltInMacroContext(
                workingDirectory: workingDirectory,
                outputDirectory: outputDirectory,
            ),
            noora: noora,
            isInteractive: isInteractive,
            override: override,
        )

        try await expander.expand(
            substituting: macros,
            with: outputs,
            excluding: config.hatch.exclude,
        )

        progress("✅ Template hatched successfully at \(outputDirectory.path(percentEncoded: false))\n", tab: 1)

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
    ///   - executionEnvironment: Execution environment (normal or staging)
    func executePostHatch(
        steps: [Config.LifecycleStep],
        macros: [ResolvedMacro],
        outputs: StepOutputsStorage,
        workingDirectory: URL,
        additionalEnvironment: [String: String] = [:],
        executionEnvironment: ExecutionEnvironment = .unsandboxed,
    ) async throws {
        progress("🐥 Post-hatch script executing...\n")

        let builtInContext = makeBuiltInMacroContext(
            workingDirectory: workingDirectory,
            additionalEnvironment: additionalEnvironment,
        )

        let stepRunner = LifecycleStepRunner(
            processRunner: processRunner,
            workingDirectory: workingDirectory,
            noora: noora,
            additionalEnvironment: additionalEnvironment,
            executionEnvironment: executionEnvironment,
            builtInMacroContext: builtInContext,
        )

        _ = try await stepRunner.execute(
            .postHatch,
            steps: steps,
            substituting: macros,
            merging: outputs,
        )
    }

    /// Emits a human-facing progress line, but only in interactive mode.
    ///
    /// Non-interactive (agent transaction) runs keep stdout clean so the JSON
    /// result is the only thing on stdout and stays machine-parseable.
    private func progress(_ message: TerminalText, tab: UInt = 0) {
        guard isInteractive else { return }
        noora.passthrough(message, tab: tab)
    }

    private func makeBuiltInMacroContext(
        workingDirectory: URL,
        outputDirectory: URL? = nil,
        additionalEnvironment: [String: String] = [:],
    ) -> BuiltInMacroContext {
        var environment = processEnvironment

        if !additionalEnvironment.isEmpty {
            environment.merge(additionalEnvironment) { _, new in new }
        }

        return BuiltInMacroContext(
            outputDirectory: outputDirectory,
            workingDirectory: workingDirectory,
            homeDirectory: homeDirectory,
            currentDate: builtInMacroDate,
            environment: environment,
        )
    }
}
