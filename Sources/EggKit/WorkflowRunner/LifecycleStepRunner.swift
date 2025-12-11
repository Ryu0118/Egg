import Foundation
import Noora
import Path
import ProcessRunning

/// Orchestrates the execution of lifecycle steps for pre_hatch and post_hatch phases.
///
/// LifecycleStepRunner coordinates the execution of lifecycle steps by:
/// 1. Evaluating conditional expressions (if field)
/// 2. Resolving variables (macros and step outputs)
/// 3. Executing shell commands
/// 4. Parsing and storing step outputs
///
/// Example:
/// ```swift
/// let runner = LifecycleStepRunner(
///     processRunner: ProcessRunner(),
///     workingDirectory: try AbsolutePath(validating: "/tmp/project")
/// )
///
/// let outputs = try await runner.execute(
///     .preHatch,
///     steps: config.lifecycle.preHatch,
///     substituting: resolvedMacros,
///     merging: StepOutputsStorage()
/// )
/// ```
struct LifecycleStepRunner {
    private let processRunner: any ProcessRunning
    private let workingDirectory: AbsolutePath
    private let noora: any Noorable
    private let additionalEnvironment: [String: String]
    private let executionEnvironment: ExecutionEnvironment

    init(
        processRunner: any ProcessRunning,
        workingDirectory: AbsolutePath,
        noora: some Noorable = Noora(),
        additionalEnvironment: [String: String] = [:],
        executionEnvironment: ExecutionEnvironment = .normal
    ) {
        self.processRunner = processRunner
        self.workingDirectory = workingDirectory
        self.noora = noora
        self.additionalEnvironment = additionalEnvironment
        self.executionEnvironment = executionEnvironment
    }

    /// Executes all steps in a lifecycle phase.
    ///
    /// - Parameters:
    ///   - phase: The lifecycle phase to execute
    ///   - steps: Steps to execute in the specified phase
    ///   - macros: Resolved macros to substitute in run commands
    ///   - previousOutputs: Outputs from previous phases to merge with new outputs
    /// - Returns: Updated output storage containing outputs from all executed steps
    /// - Throws: `LifecycleStepError` if any step fails
    func execute(
        _ phase: LifecyclePhase,
        steps: [Config.LifecycleStep],
        substituting macros: [ResolvedMacro],
        merging previousOutputs: StepOutputsStorage
    ) async throws -> StepOutputsStorage {
        let outputs = previousOutputs

        for step in steps {
            try await executeStep(step, in: phase, substituting: macros, storingTo: outputs)
        }

        return outputs
    }

    /// Executes a single lifecycle step.
    ///
    /// Evaluates the step's condition, resolves variables in the run command,
    /// executes the shell command, and stores any outputs.
    ///
    /// - Parameters:
    ///   - step: The lifecycle step to execute
    ///   - phase: The current lifecycle phase
    ///   - macros: Resolved macros for variable substitution
    ///   - outputs: Storage for step outputs
    private func executeStep(
        _ step: Config.LifecycleStep,
        in phase: LifecyclePhase,
        substituting macros: [ResolvedMacro],
        storingTo outputs: StepOutputsStorage
    ) async throws {
        guard try await shouldExecute(step, given: macros, and: outputs) else {
            return
        }

        guard let resolvedCommand = try await resolveCommand(from: step, substituting: macros, referencing: outputs) else {
            return
        }

        let shellRunner = ShellScriptRunner(
            processRunner: processRunner,
            workingDirectory: workingDirectory,
            additionalEnvironment: additionalEnvironment,
            executionEnvironment: executionEnvironment
        )
        let stdout = try await shellRunner.executeStreaming(resolvedCommand) { output in
            noora.passthrough("\(output)\n", tab: 1)
        }

        if let stepId = step.id {
            let parsedOutputs = StepOutputParser.parse(stdout)
            await outputs.store(phase: phase, stepId: stepId, outputs: parsedOutputs)
        }
    }

    /// Evaluates whether a step should be executed based on its condition.
    ///
    /// - Parameters:
    ///   - step: The step to evaluate
    ///   - macros: Resolved macros for condition evaluation
    ///   - outputs: Step outputs for condition evaluation
    /// - Returns: `true` if the step should execute, `false` if it should be skipped
    private func shouldExecute(
        _ step: Config.LifecycleStep,
        given macros: [ResolvedMacro],
        and outputs: StepOutputsStorage
    ) async throws -> Bool {
        guard let condition = step.if else {
            return true
        }

        let evaluator = ConditionEvaluator(macros: macros, outputs: outputs)
        return try await evaluator.evaluate(condition)
    }

    /// Resolves variables in a step's run command.
    ///
    /// - Parameters:
    ///   - step: The step containing the run command
    ///   - macros: Resolved macros for substitution
    ///   - outputs: Step outputs for variable references
    /// - Returns: The resolved command string, or `nil` if the step has no run command
    private func resolveCommand(
        from step: Config.LifecycleStep,
        substituting macros: [ResolvedMacro],
        referencing outputs: StepOutputsStorage
    ) async throws -> String? {
        guard let runCommand = step.run else {
            return nil
        }

        let resolver = VariableResolver(macros: macros, outputs: outputs)
        return try await resolver.resolve(runCommand)
    }
}
