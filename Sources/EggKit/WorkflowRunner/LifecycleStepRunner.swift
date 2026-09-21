import Foundation
import Interaction
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
///     workingDirectory: URL(filePath: "/tmp/project")
/// )
///
/// let outputs = try await runner.execute(
///     .preHatch,
///     steps: config.lifecycle.preHatch,
///     substituting: resolvedMacros,
///     merging: StepOutputsStorage()
/// )
/// ```
/// Collects stdout chunks as they stream in, so output survives a step that
/// throws. Mirrors `LineStreamer`'s contract: the streaming closure calls it
/// serially from the awaiting context.
private final class CapturedOutput {
    private(set) var text = ""

    /// Tracks `text`'s UTF-8 byte count incrementally so `append` doesn't
    /// re-scan the whole accumulated string on every chunk.
    private var byteCount = 0

    /// Stops accumulating once past what the collector would keep anyway.
    /// A `pre_hatch` step running a build can print megabytes, and this
    /// buffer duplicates what `executeStreaming` already holds.
    func append(_ chunk: String) {
        guard byteCount < LifecycleScriptOutput.byteLimit else { return }
        text += chunk
        byteCount += chunk.utf8.count
    }
}

struct LifecycleStepRunner {
    private let processRunner: any ProcessRunning
    private let workingDirectory: URL
    private let interaction: any InteractionProviding
    private let additionalEnvironment: [String: String]
    private let executionEnvironment: ExecutionEnvironment
    private let builtInMacroContext: BuiltInMacroContext
    private let suppressHumanProgress: Bool
    private let outputCollector: LifecycleScriptOutputCollector?

    init(
        processRunner: any ProcessRunning,
        workingDirectory: URL,
        interaction: some InteractionProviding = GuardedTerminal(),
        additionalEnvironment: [String: String] = [:],
        executionEnvironment: ExecutionEnvironment = .unsandboxed,
        builtInMacroContext: BuiltInMacroContext,
        suppressHumanProgress: Bool = false,
        outputCollector: LifecycleScriptOutputCollector? = nil,
    ) {
        self.processRunner = processRunner
        self.workingDirectory = workingDirectory
        self.interaction = interaction
        self.additionalEnvironment = additionalEnvironment
        self.executionEnvironment = executionEnvironment
        self.builtInMacroContext = builtInMacroContext
        self.suppressHumanProgress = suppressHumanProgress
        self.outputCollector = outputCollector
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
        merging previousOutputs: StepOutputsStorage,
    ) async throws -> StepOutputsStorage {
        let outputs = previousOutputs

        for (index, step) in steps.enumerated() {
            try await executeStep(step, at: index, in: phase, substituting: macros, storingTo: outputs)
        }

        return outputs
    }

    /// Emits a human-facing progress line, unless stdout is reserved for JSON.
    ///
    /// Only the agent transaction flow suppresses these: its JSON result is
    /// the sole thing on stdout and must stay machine-parseable. Every other
    /// run — including non-interactive `egg hatch direct` — shows them, which
    /// is how a template author's script output reaches a human.
    private func progress(_ message: StyledText, tab: UInt) {
        guard !suppressHumanProgress else { return }
        interaction.writeLine(message, tab: tab)
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
        at index: Int,
        in phase: LifecyclePhase,
        substituting macros: [ResolvedMacro],
        storingTo outputs: StepOutputsStorage,
    ) async throws {
        let stepLabel = formatStepLabel(phase: phase, index: index, stepId: step.id)

        guard try await shouldExecute(step, given: macros, and: outputs) else {
            progress("⏭️ \(stepLabel): Skipped (condition not met)", tab: 1)
            await outputCollector?.recordSkipped(phase: phase, index: index, id: step.id)
            return
        }

        guard let resolvedCommand = try await resolveCommand(from: step, substituting: macros, referencing: outputs) else {
            return
        }

        progress("🦆 \(stepLabel): Running script...", tab: 1)

        let shellRunner = ShellScriptRunner(
            processRunner: processRunner,
            workingDirectory: workingDirectory,
            additionalEnvironment: additionalEnvironment,
            executionEnvironment: executionEnvironment,
        )
        let lineStreamer = LineStreamer { line in
            progress("\(line)", tab: 2)
        }
        // Accumulate here rather than relying on executeStreaming's return
        // value: a step that exits non-zero throws, and its output — usually
        // the most useful output there is — would be lost with it.
        let captured = CapturedOutput()
        let stdout: String
        do {
            stdout = try await shellRunner.executeStreaming(resolvedCommand) { chunk in
                captured.append(chunk)
                lineStreamer.append(chunk)
            }
        } catch {
            lineStreamer.flush()
            await outputCollector?.record(phase: phase, index: index, id: step.id, stdout: captured.text)
            throw error
        }
        lineStreamer.flush()

        await outputCollector?.record(phase: phase, index: index, id: step.id, stdout: stdout)

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
        and outputs: StepOutputsStorage,
    ) async throws -> Bool {
        guard let condition = step.if else {
            return true
        }

        let evaluator = ConditionEvaluator(
            macros: macros,
            outputs: outputs,
            builtInMacroContext: builtInMacroContext,
        )
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
        referencing outputs: StepOutputsStorage,
    ) async throws -> String? {
        guard let runCommand = step.run else {
            return nil
        }

        let resolver = VariableResolver(
            macros: macros,
            outputs: outputs,
            builtInMacroContext: builtInMacroContext,
        )
        return try await resolver.resolve(runCommand, destination: .shellCommand)
    }

    /// Formats a step label for logging purposes.
    ///
    /// - Parameters:
    ///   - phase: The lifecycle phase
    ///   - index: The step index
    ///   - stepId: Optional step identifier
    /// - Returns: Formatted label like "pre_hatch.run[0]" or "pre_hatch.run[0](my_step)"
    private func formatStepLabel(phase: LifecyclePhase, index: Int, stepId: String?) -> String {
        if let stepId {
            "\(phase.rawValue).run[\(index)](\(stepId))"
        } else {
            "\(phase.rawValue).run[\(index)]"
        }
    }
}
