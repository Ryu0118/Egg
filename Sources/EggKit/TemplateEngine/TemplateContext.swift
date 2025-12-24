/// Context for template rendering.
///
/// This structure holds all the data needed to render a template,
/// including user-defined macros, step outputs, and built-in macro context.
struct TemplateContext: Sendable {
    /// User-defined macros resolved from config.yml.
    let macros: [ResolvedMacro]

    /// Step outputs from pre_hatch and post_hatch lifecycle phases.
    let outputs: StepOutputsStorage

    /// Context for resolving built-in macros (___DATE___, ___UUID___, etc.).
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
}
