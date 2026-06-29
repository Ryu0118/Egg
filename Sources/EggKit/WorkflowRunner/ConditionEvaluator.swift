import Foundation
import JavaScriptCore

/// Evaluates conditional expressions for lifecycle step execution.
///
/// This evaluator uses JSEvaluator for JavaScript-like expression evaluation with
/// type-aware variable expansion. Conditions support operators like `===`, `!==`,
/// `&&`, `||`, and array methods like `.includes()`.
///
/// **IMPORTANT**: ConditionEvaluator uses different quoting rules than VariableResolver:
/// - VariableResolver (for `run` fields): Direct string replacement, NO quoting
/// - ConditionEvaluator (for `if` fields): Type-aware quoting for JavaScript evaluation
struct ConditionEvaluator {
    let macros: [ResolvedMacro]
    let outputs: StepOutputsStorage
    let builtInMacroContext: BuiltInMacroContext

    /// Evaluates a conditional expression.
    ///
    /// The evaluation process:
    /// 1. First pass: Resolve macros with type-aware quoting
    /// 2. Second pass: Resolve step output references with quoting
    /// 3. JavaScript evaluation: Use JSEvaluator to evaluate the final expression
    ///
    /// - Parameter condition: The condition string from config.yaml (e.g., "___DEBUG___ === true")
    /// - Returns: Boolean indicating whether the step should execute
    /// - Throws: `LifecycleStepError.conditionEvaluationError` if evaluation fails
    func evaluate(_ condition: String) async throws -> Bool {
        // Pass 1: Resolve macros with type-aware quoting
        var result = resolveMacros(condition)

        // Pass 2: Resolve step output references with quoting
        result = try await resolveStepOutputs(result)

        // Pass 3: JavaScript evaluation
        return try evaluateJavaScript(result)
    }

    /// Replaces all `___MACRO_NAME___` patterns with their resolved values using type-aware quoting.
    ///
    /// Quoting rules for JavaScript evaluation:
    /// - `.string(s)` → `"s"` (quoted)
    /// - `.boolean(b)` → `true` or `false` (unquoted)
    /// - `.choice(c)` → `"c"` (quoted)
    /// - `.array(a)` → `["item1", "item2"]` (JSON array)
    /// - `.path(p)` → `"path"` (quoted, resolved absolute path)
    private func resolveMacros(_ text: String) -> String {
        var result = text

        for macro in macros {
            let stringValue = MacroStringConverter.toJavaScriptLiteral(
                macro.value,
                workingDirectory: builtInMacroContext.workingDirectory,
                homeDirectory: builtInMacroContext.homeDirectory,
            )
            result = result.replacingOccurrences(of: macro.name, with: stringValue)
        }

        return result
    }

    /// Replaces all `${{ phase.step-id.outputs.key }}` patterns with their values.
    ///
    /// Step outputs are strings from stdout and are replaced directly without quoting.
    ///
    /// Pattern components:
    /// - `phase`: pre_hatch or post_hatch
    /// - `step-id`: step identifier (alphanumeric, hyphens, underscores)
    /// - `key`: output key name (alphanumeric, hyphens, underscores, dots)
    ///
    /// - Throws: `LifecycleStepError.undefinedOutputReference` if output not found
    private func resolveStepOutputs(_ text: String) async throws -> String {
        let regex = Regexes.stepOutputDetailed
        var result = text

        // Process matches in reverse order to maintain correct string indices
        let matches = result.matches(of: regex).reversed()

        for match in matches {
            let phase = String(match.output.1)
            let stepId = String(match.output.2)
            let key = String(match.output.3)

            // Lookup value in storage
            let value = try await getOutputValue(phase: phase, stepId: stepId, key: key)

            // Replace the entire pattern with the value directly (no quoting)
            result.replaceSubrange(match.range, with: value)
        }

        return result
    }

    /// Retrieves an output value from storage.
    ///
    /// - Throws: `LifecycleStepError.undefinedOutputReference` if the reference cannot be resolved
    private func getOutputValue(phase: String, stepId: String, key: String) async throws -> String {
        guard let phaseEnum = LifecyclePhase(rawValue: phase) else {
            // This should never happen as regex only matches valid phase strings
            // But if it does, use .preHatch as fallback for error reporting
            throw LifecycleStepError.undefinedOutputReference(
                phase: .preHatch,
                stepId: stepId,
                key: key,
            )
        }

        guard let value = await outputs.get(phase: phaseEnum, stepId: stepId, key: key) else {
            throw LifecycleStepError.undefinedOutputReference(
                phase: phaseEnum,
                stepId: stepId,
                key: key,
            )
        }

        return value
    }

    /// Evaluates a JavaScript expression using JSEvaluator.
    ///
    /// - Parameter expression: JavaScript expression to evaluate (e.g., "true === true")
    /// - Returns: Boolean result of the evaluation
    /// - Throws: `LifecycleStepError.conditionEvaluationError` if evaluation fails or returns non-boolean
    private func evaluateJavaScript(_ expression: String) throws -> Bool {
        let evaluator = JSEvaluator()

        guard let result = evaluator.evaluate(expression) else {
            throw LifecycleStepError.conditionEvaluationError(
                condition: expression,
                reason: "JavaScript evaluation failed or returned null/undefined",
            )
        }

        guard result.isBoolean else {
            throw LifecycleStepError.conditionEvaluationError(
                condition: expression,
                reason: "Condition must evaluate to a boolean, got: \(result)",
            )
        }

        return result.toBool()
    }
}
