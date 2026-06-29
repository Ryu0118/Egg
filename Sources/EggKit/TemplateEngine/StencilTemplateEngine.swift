import Foundation
import Stencil

/// Stencil template engine for `.stencil` files.
///
/// This engine handles Stencil template syntax:
/// - `{{ ___MACRO___ }}`: Variable output using egg macro names
/// - `{% if ___CONDITION___ %}`: Conditional blocks
/// - `{% for item in ___ARRAY___ %}`: Loop blocks
/// - `{{ pre_hatch.step.outputs.key }}`: Step output access
///
/// Processing order:
/// 1. Resolve built-in macros (___DATE___, ___UUID___, etc.) - these are resolved before Stencil
/// 2. Build Stencil context from macros and step outputs
/// 3. Render with Stencil engine
struct StencilTemplateEngine: TemplateEngine {
    func render(_ content: String, with context: TemplateContext) async throws -> String {
        // 1. Resolve built-in macros first (before Stencil processing)
        let contentWithBuiltIns = BuiltInMacros.resolve(content, context: context.builtInMacroContext)

        // 2. Build Stencil context
        let stencilContext = await buildStencilContext(from: context)

        // 3. Render with Stencil
        let environment = Environment()
        do {
            return try environment.renderTemplate(string: contentWithBuiltIns, context: stencilContext)
        } catch let error as TemplateSyntaxError {
            throw Error.syntaxError(message: error.description)
        } catch let error as TemplateDoesNotExist {
            throw Error.templateNotFound(name: error.description)
        } catch {
            throw Error.renderingFailed(underlyingError: error)
        }
    }

    /// Builds a Stencil context dictionary from the template context.
    ///
    /// Macro conversion:
    /// - `___PROJECT_NAME___` (string: "MyApp") → `{ "___PROJECT_NAME___": "MyApp" }`
    /// - `___USE_ASYNC___` (boolean: true) → `{ "___USE_ASYNC___": true }`
    /// - `___MODULES___` (choices: ["A", "B"]) → `{ "___MODULES___": ["A", "B"] }`
    ///
    /// Step outputs conversion:
    /// - `outputs.get(phase: .preHatch, stepId: "setup", key: "version")` = "1.0.0"
    /// - → `{ "pre_hatch": { "setup": { "outputs": { "version": "1.0.0" } } } }`
    private func buildStencilContext(from context: TemplateContext) async -> [String: Any] {
        // Add macros
        var dict: [String: Any] = context.macros.reduce(into: [:]) { result, macro in
            result[macro.name] = convertMacroValue(macro.value)
        }

        // Add step outputs (nested structure for dot-notation access)
        let outputs = await context.outputs.allOutputsForStencil()
        dict.merge(outputs) { _, new in new }

        return dict
    }

    /// Converts a macro value to a Stencil-compatible type.
    private func convertMacroValue(_ value: ResolvedMacro.Value) -> Any {
        switch value {
        case let .string(s):
            s
        case let .boolean(b):
            b
        case let .choice(c):
            c
        case let .choices(c):
            c
        case let .array(a):
            a
        case let .path(url):
            url.path(percentEncoded: false)
        }
    }
}

extension StencilTemplateEngine {
    /// Errors that can occur during Stencil template rendering.
    enum Error: LocalizedError {
        case syntaxError(message: String)
        case templateNotFound(name: String)
        case renderingFailed(underlyingError: Swift.Error)

        var errorDescription: String? {
            switch self {
            case let .syntaxError(message):
                "Stencil syntax error: \(message)"
            case let .templateNotFound(name):
                "Stencil template not found: \(name)"
            case let .renderingFailed(underlyingError):
                "Stencil rendering failed: \(underlyingError.localizedDescription)"
            }
        }
    }
}
