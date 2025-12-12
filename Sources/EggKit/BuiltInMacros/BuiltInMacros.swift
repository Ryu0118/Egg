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
package enum BuiltInMacros {
    /// Current date in default format (yyyy-MM-dd) or custom format.
    ///
    /// - `___DATE___` → `2025-12-12`
    /// - `___DATE(yyyyMMdd)___` → `20251212`
    package static let DATE = BuiltInMacro.declareWithArgument("___DATE___") { argument, context in
        formatDate(context.currentDate, format: argument ?? "yyyy-MM-dd")
    }

    /// Current year.
    ///
    /// - `___YEAR___` → `2025`
    package static let YEAR = BuiltInMacro.declare("___YEAR___") { context in
        formatDate(context.currentDate, format: "yyyy")
    }

    /// Current system username.
    ///
    /// - `___SYSTEM_USER___` → `ryu`
    package static let SYSTEM_USER = BuiltInMacro.declare("___SYSTEM_USER___") { context in
        context.environment["USER"] ?? NSUserName()
    }

    /// Newly generated UUID (unique per occurrence).
    ///
    /// - `___UUID___` → `550e8400-e29b-41d4-a716-446655440000`
    package static let UUID = BuiltInMacro.declare("___UUID___") { _ in
        Foundation.UUID().uuidString
    }

    /// All registered built-in macros.
    package static let all: [BuiltInMacro] = [
        DATE,
        YEAR,
        SYSTEM_USER,
        UUID,
    ]

    /// All reserved macro names that cannot be used by users.
    package static let reservedNames: Set<String> = Set(all.map(\.name))

    /// Checks if a macro name is reserved (built-in).
    package static func isReserved(_ name: String) -> Bool {
        reservedNames.contains(name)
    }

    /// Resolves all built-in macros in the given text.
    package static func resolve(_ text: String, context: BuiltInMacroContext) -> String {
        var result = text

        for macro in all {
            result = resolveMacro(macro, in: result, context: context)
        }

        return result
    }
}

private extension BuiltInMacros {
    static func resolveMacro(
        _ macro: BuiltInMacro,
        in text: String,
        context: BuiltInMacroContext
    ) -> String {
        let pattern = makePattern(for: macro)

        var result = text
        let matches = Array(text.matches(of: pattern).reversed())

        for match in matches {
            let matchedString = String(text[match.range])
            let resolved = macro.resolve(matchedString, context)
            result.replaceSubrange(match.range, with: resolved)
        }

        return result
    }

    static func makePattern(for macro: BuiltInMacro) -> Regex<AnyRegexOutput> {
        if macro.acceptsArgument {
            // Match both ___NAME___ and ___NAME(arg)___
            let baseName = String(macro.name.dropFirst(3).dropLast(3)) // DATE
            let pattern = "___\(baseName)(?:\\([^)]+\\))?___"
            return try! Regex(pattern).matchingSemantics(.graphemeCluster)
        } else {
            // Match exact name only
            let escaped = NSRegularExpression.escapedPattern(for: macro.name)
            return try! Regex(escaped).matchingSemantics(.graphemeCluster)
        }
    }

    static func formatDate(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }
}
