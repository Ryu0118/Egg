import Foundation

/// Resolves variables (macros and step outputs) in strings.
///
/// This resolver performs two-pass variable substitution:
/// 1. First pass: Replace `___MACRO_NAME___` with resolved macro values
/// 2. Second pass: Replace `${{ phase.step-id.outputs.key }}` with step outputs
///
/// The two-pass design ensures macros are fully resolved before output references,
/// preventing ambiguity and enabling macros to be used in output reference patterns.
struct VariableResolver {
    let macros: [ResolvedMacro]
    let outputs: StepOutputsStorage
    let builtInMacroContext: BuiltInMacroContext

    init(
        macros: [ResolvedMacro],
        outputs: StepOutputsStorage,
        builtInMacroContext: BuiltInMacroContext
    ) {
        self.macros = macros
        self.outputs = outputs
        self.builtInMacroContext = builtInMacroContext
    }

    /// Resolves all variables in the given text.
    ///
    /// - Parameter text: Text containing variable references to resolve
    /// - Returns: Text with all variables resolved
    /// - Throws: `LifecycleStepError.undefinedOutputReference` if an output reference cannot be resolved
    func resolve(_ text: String) async throws -> String {
        var result = resolveBuiltInMacros(text)

        result = resolveMacros(result)

        result = try await resolveStepOutputs(result)

        return result
    }

    /// Replaces all built-in macros (e.g., ___DATE___) before user-defined macros.
    private func resolveBuiltInMacros(_ text: String) -> String {
        BuiltInMacros.resolve(text, context: builtInMacroContext)
    }

    /// Replaces all `___MACRO_NAME___` patterns with their resolved values.
    private func resolveMacros(_ text: String) -> String {
        macros.reduce(text) { result, macro in
            let stringValue = MacroStringConverter.toShellString(
                macro.value,
                workingDirectory: builtInMacroContext.workingDirectory,
                homeDirectory: builtInMacroContext.homeDirectory
            )
            return result.replacingOccurrences(of: macro.name, with: stringValue)
        }
    }

    /// Replaces all `${{ phase.step-id.outputs.key }}` patterns with their values.
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
            let value = try await getOutputValue(from: outputs, phase: phase, stepId: stepId, key: key)

            // Replace the entire pattern with the resolved value
            result.replaceSubrange(match.range, with: value)
        }

        return result
    }

    /// Retrieves an output value from storage.
    ///
    /// - Throws: `LifecycleStepError.undefinedOutputReference` if the reference cannot be resolved
    private func getOutputValue(
        from outputs: StepOutputsStorage,
        phase: String,
        stepId: String,
        key: String
    ) async throws -> String {
        guard let phaseEnum = LifecyclePhase(rawValue: phase) else {
            throw LifecycleStepError.undefinedOutputReference(
                phase: .preHatch,
                stepId: stepId,
                key: key
            )
        }

        guard let value = await outputs.get(phase: phaseEnum, stepId: stepId, key: key) else {
            throw LifecycleStepError.undefinedOutputReference(
                phase: phaseEnum,
                stepId: stepId,
                key: key
            )
        }

        return value
    }
}
