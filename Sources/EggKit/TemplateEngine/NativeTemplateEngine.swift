/// Native template engine for `___MACRO___` and `${{ outputs }}` patterns.
///
/// This engine handles the original egg template syntax:
/// - `___MACRO_NAME___`: User-defined macro substitution
/// - `${{ phase.step.outputs.key }}`: Step output references
/// - `___DATE___`, `___UUID___`, etc.: Built-in macros
///
/// Processing order:
/// 1. Resolve built-in macros (___DATE___, ___UUID___, etc.)
/// 2. Resolve user-defined macros (___PROJECT_NAME___, etc.)
/// 3. Resolve step outputs (${{ pre_hatch.setup.outputs.version }})
struct NativeTemplateEngine: TemplateEngine {
    func render(_ content: String, with context: TemplateContext) async throws -> String {
        let resolver = VariableResolver(
            macros: context.macros,
            outputs: context.outputs,
            builtInMacroContext: context.builtInMacroContext,
        )
        return try await resolver.resolve(content)
    }
}
