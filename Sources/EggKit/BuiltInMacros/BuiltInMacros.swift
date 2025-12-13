import Foundation

/// Static declarations of all built-in macros.
///
/// Usage:
/// ```swift
/// // Access macro name
/// let name = BuiltInMacros.DATE.name  // "___DATE___"
///
/// // Check if a name is reserved
/// BuiltInMacros.isReserved("___DATE___")  // true
///
/// // Resolve all built-in macros in text
/// let resolved = BuiltInMacros.resolve("Today is ___DATE___", context: context)
/// ```
enum BuiltInMacros {
    /// Current date in default format (yyyy-MM-dd) or custom format.
    ///
    /// - `___DATE___` → `2025-12-12`
    /// - `___DATE(yyyyMMdd)___` → `20251212`
    static let DATE = BuiltInMacro.declareWithArgument("___DATE___") { argument, context in
        formatDate(context.currentDate, format: argument)
    }

    /// Current year.
    ///
    /// - `___YEAR___` → `2025`
    static let YEAR = BuiltInMacro.declare("___YEAR___") { context in
        formatDate(context.currentDate, format: "yyyy")
    }

    /// Current system username.
    ///
    /// - `___SYSTEM_USER___` → `ryu`
    static let SYSTEM_USER = BuiltInMacro.declare("___SYSTEM_USER___") { context in
        context.environment["USER"] ?? NSUserName()
    }

    /// Newly generated UUID (unique per occurrence).
    ///
    /// - `___UUID___` → `550e8400-e29b-41d4-a716-446655440000`
    static let UUID = BuiltInMacro.declare("___UUID___") { _ in
        Foundation.UUID().uuidString
    }

    /// All registered built-in macros.
    static let all: [BuiltInMacro] = [
        DATE,
        YEAR,
        SYSTEM_USER,
        UUID,
    ]

    /// All reserved macro names that cannot be used by users.
    static let reservedNames: Set<String> = Set(all.map(\.name))

    /// Checks if a macro name is reserved (built-in).
    static func isReserved(_ name: String) -> Bool {
        reservedNames.contains(name)
    }

    /// Resolves all built-in macros in the given text.
    static func resolve(_ text: String, context: BuiltInMacroContext) -> String {
        var result = text

        for macro in all {
            result = resolveMacro(macro, in: result, context: context)
        }

        return result
    }

    static func formatDate(_ date: Date, format: String?) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format ?? DateFormatter.dateFormat(
            fromTemplate: "ydMMM",
            options: 0,
            locale: .current
        )
        return formatter.string(from: date)
    }
}

private extension BuiltInMacros {
    static func resolveMacro(
        _ macro: BuiltInMacro,
        in text: String,
        context: BuiltInMacroContext
    ) -> String {
        let baseName = String(macro.name.dropFirst(3).dropLast(3))
        return if macro.acceptsArgument {
            resolveWithPattern(macro, in: text, context: context, pattern: Regexes.macroWithArgument(name: baseName))
        } else {
            resolveWithPattern(macro, in: text, context: context, pattern: Regexes.exactMacro(name: baseName))
        }
    }

    static func resolveWithPattern<R: RegexComponent>(
        _ macro: BuiltInMacro,
        in text: String,
        context: BuiltInMacroContext,
        pattern: R
    ) -> String {
        var result = text
        let matches = Array(text.matches(of: pattern).reversed())

        for match in matches {
            let matchedString = String(text[match.range])
            let resolved = macro.resolve(matchedString, context)
            result.replaceSubrange(match.range, with: resolved)
        }

        return result
    }
}
