import Foundation

/// Resolves variables (macros and step outputs) in strings.
///
/// This resolver performs two-pass variable substitution:
/// 1. First pass: Replace `___MACRO_NAME___` with resolved macro values
/// 2. Second pass: Replace `${{ phase.step-id.outputs.key }}` with step outputs
///
/// The two-pass design ensures macros are fully resolved before output references,
/// preventing ambiguity and enabling macros to be used in output reference patterns.
///
/// This resolver is shared by several very different consumers, distinguished by `resolve(_:destination:)`:
/// - `NativeTemplateEngine` renders plain file content — substituted values must appear verbatim,
///   and unknown `${{ }}` phases belong to the file's own target format (see `.fileContent`).
/// - `TemplateExpander` / `PhaseRunner` / `SandboxAllowedPathsResolver` resolve paths and config
///   values — substituted values appear verbatim, and every `${{ }}` is egg's own DSL (see `.text`).
/// - `LifecycleStepRunner` builds a `/bin/sh -c` command string — substituted values must be
///   shell-quoted, since they may originate from an untrusted MCP caller's `macros` argument
///   or from a step's captured stdout, and raw substitution would let shell metacharacters
///   (`;`, `$()`, backticks, `|`) escape the intended single argument.
struct VariableResolver {
    /// Where the resolved text will be used, which determines whether substituted
    /// values need shell quoting and how unknown `${{ }}` phases are treated.
    enum Destination {
        /// Plain-text output for egg's own inputs (paths, `hatch.output`, `sandbox.allowed_paths`)
        /// — substitute values verbatim, and treat every `${{ }}` reference as egg DSL, so an
        /// unrecognized phase is a typo worth reporting.
        case text
        /// The body of a template file — substitute values verbatim, but leave `${{ }}` references
        /// whose phase is not an egg `LifecyclePhase` completely untouched.
        ///
        /// A generated file's own format frequently owns the `${{ … }}` spelling: GitHub Actions
        /// workflows write `${{ steps.build.outputs.sha }}` and `${{ needs.test.outputs.version }}`,
        /// which are structurally indistinguishable from egg's `${{ pre_hatch.step.outputs.key }}`.
        /// Resolving them would abort the whole hatch on a reference the template never meant for
        /// egg, so only the phases egg actually defines are claimed here.
        case fileContent
        /// A `/bin/sh -c` command string — substitute values as shell-quoted literals.
        case shellCommand
    }

    let macros: [ResolvedMacro]
    let outputs: StepOutputsStorage
    let builtInMacroContext: BuiltInMacroContext

    /// Resolves all variables in the given text.
    ///
    /// - Parameters:
    ///   - text: Text containing variable references to resolve
    ///   - destination: Whether the result is plain text or a shell command (default `.text`)
    /// - Returns: Text with all variables resolved
    /// - Throws: `LifecycleStepError.undefinedOutputReference` if an output reference cannot be resolved
    func resolve(_ text: String, destination: Destination = .text) async throws -> String {
        var result = resolveBuiltInMacros(text)

        result = resolveMacros(result, destination: destination)

        result = try await resolveStepOutputs(result, destination: destination)

        return result
    }

    /// Replaces all built-in macros (e.g., ___DATE___) before user-defined macros.
    private func resolveBuiltInMacros(_ text: String) -> String {
        BuiltInMacros.resolve(text, context: builtInMacroContext)
    }

    /// Replaces all `___MACRO_NAME___` patterns with their resolved values.
    ///
    /// For `.shellCommand`, each value is wrapped in single quotes (see
    /// `MacroStringConverter.shellQuote`) so it substitutes as one literal shell word —
    /// templates should NOT wrap `___MACRO___` in their own quotes in a `run:` command;
    /// the substitution is already a safe, standalone shell token.
    private func resolveMacros(_ text: String, destination: Destination) -> String {
        macros.reduce(text) { result, macro in
            let rawValue = MacroStringConverter.toShellString(
                macro.value,
                workingDirectory: builtInMacroContext.workingDirectory,
                homeDirectory: builtInMacroContext.homeDirectory,
            )
            let stringValue = destination == .shellCommand ? MacroStringConverter.shellQuote(rawValue) : rawValue
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
    private func resolveStepOutputs(_ text: String, destination: Destination) async throws -> String {
        let regex = Regexes.stepOutputDetailed
        var result = text

        // Process matches in reverse order to maintain correct string indices
        let matches = result.matches(of: regex).reversed()

        for match in matches {
            let phase = String(match.output.1)
            let stepId = String(match.output.2)
            let key = String(match.output.3)

            // In a template file's body, a phase egg does not define belongs to the file's own
            // format (e.g. GitHub Actions' `steps.` / `needs.`), not to egg. Leave it verbatim.
            if destination == .fileContent, LifecyclePhase(rawValue: phase) == nil {
                continue
            }

            // Lookup value in storage
            let value = try await getOutputValue(from: outputs, phase: phase, stepId: stepId, key: key)
            let stringValue = destination == .shellCommand ? MacroStringConverter.shellQuote(value) : value

            // Replace the entire pattern with the resolved value
            result.replaceSubrange(match.range, with: stringValue)
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
        key: String,
    ) async throws -> String {
        guard let phaseEnum = LifecyclePhase(rawValue: phase) else {
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
}
