import Foundation

/// A built-in macro definition.
///
/// Built-in macros are automatically available without explicit definition in config.yaml.
/// Each macro has a name pattern and a resolver that computes its value at runtime.
struct BuiltInMacro {
    /// The macro name (e.g., `___DATE___`).
    let name: String

    /// Whether this macro accepts an argument (e.g., `___DATE(yyyyMMdd)___`, `___ENV(PATH)___`).
    let acceptsArgument: Bool

    /// The resolver that computes the macro value.
    let resolve: @Sendable (String, BuiltInMacroContext) -> String

    private init(
        name: String,
        acceptsArgument: Bool = false,
        resolve: @escaping @Sendable (String, BuiltInMacroContext) -> String,
    ) {
        self.name = name
        self.acceptsArgument = acceptsArgument
        self.resolve = resolve
    }
}

extension BuiltInMacro {
    /// Declares a simple built-in macro with a static value resolver.
    static func declare(
        _ name: String,
        resolve: @escaping @Sendable (BuiltInMacroContext) -> String,
    ) -> BuiltInMacro {
        BuiltInMacro(name: name) { _, context in
            resolve(context)
        }
    }

    /// Declares a built-in macro that accepts an argument.
    ///
    /// Examples:
    /// - `___DATE(yyyyMMdd)___` where `yyyyMMdd` is the argument
    /// - `___ENV(PATH)___` where `PATH` is the argument
    static func declareWithArgument(
        _ name: String,
        resolve: @escaping @Sendable (String?, BuiltInMacroContext) -> String,
    ) -> BuiltInMacro {
        BuiltInMacro(name: name, acceptsArgument: true) { matchedString, context in
            let argument = extractArgument(from: matchedString, macroName: name)
            return resolve(argument, context)
        }
    }

    private static func extractArgument(from matchedString: String, macroName: String) -> String? {
        // ___DATE(yyyyMMdd)___ -> yyyyMMdd
        // ___DATE___ -> nil
        let prefix = String(macroName.dropLast(3)) + "(" // ___DATE(
        let suffix = ")___"

        guard matchedString.hasPrefix(prefix), matchedString.hasSuffix(suffix) else {
            return nil
        }

        let start = matchedString.index(matchedString.startIndex, offsetBy: prefix.count)
        let end = matchedString.index(matchedString.endIndex, offsetBy: -suffix.count)

        guard start < end else { return nil }

        return String(matchedString[start ..< end])
    }
}
