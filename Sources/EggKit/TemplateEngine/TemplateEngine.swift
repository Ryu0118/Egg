/// Protocol for template engines that render content with variable substitution.
///
/// Implementations:
/// - `NativeTemplateEngine`: Handles `___MACRO___` and `${{ outputs }}` patterns
/// - `StencilTemplateEngine`: Handles `.stencil` files with `{{ }}` and `{% %}` syntax
protocol TemplateEngine: Sendable {
    /// Renders the given content by substituting variables from the context.
    ///
    /// - Parameters:
    ///   - content: The template content to render
    ///   - context: The context containing macros, outputs, and built-in macro context
    /// - Returns: The rendered content with all variables resolved
    /// - Throws: An error if rendering fails (e.g., undefined variable, syntax error)
    func render(_ content: String, with context: TemplateContext) async throws -> String
}
