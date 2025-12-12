import Foundation

/// Converts ResolvedMacro values to string representations.
///
/// Provides two conversion modes:
/// - **Shell mode**: For use in shell scripts (no quoting)
/// - **JavaScript mode**: For use in JS evaluation (type-aware quoting)
enum MacroStringConverter {
    /// Converts a macro value to a string for shell scripts (no quoting).
    ///
    /// Conversion rules:
    /// - `.string(s)` → `s`
    /// - `.boolean(b)` → `"true"` or `"false"`
    /// - `.choice(c)` → `c`
    /// - `.array(a)` → `"item1,item2,item3"` (comma-separated)
    /// - `.path(p)` → `p.path(percentEncoded: false)`
    static func toShellString(_ value: ResolvedMacro.Value) -> String {
        switch value {
        case let .string(s):
            return s
        case let .boolean(b):
            return b ? "true" : "false"
        case let .choice(c):
            return c
        case let .array(a):
            return a.joined(separator: ",")
        case let .path(p):
            return p.path(percentEncoded: false)
        }
    }

    /// Converts a macro value to a JavaScript literal with type-aware quoting.
    ///
    /// Conversion rules for JavaScript evaluation:
    /// - `.string(s)` → `"s"` (quoted)
    /// - `.boolean(b)` → `true` or `false` (unquoted)
    /// - `.choice(c)` → `"c"` (quoted)
    /// - `.array(a)` → `["item1", "item2"]` (JSON array)
    /// - `.path(p)` → `"path"` (quoted)
    static func toJavaScriptLiteral(_ value: ResolvedMacro.Value) -> String {
        switch value {
        case let .string(s):
            return escapeAndQuote(s)
        case let .boolean(b):
            return b ? "true" : "false"
        case let .choice(c):
            return escapeAndQuote(c)
        case let .array(a):
            // Convert to JSON array: ["item1", "item2"]
            let quotedItems = a.map { escapeAndQuote($0) }
            return "[" + quotedItems.joined(separator: ", ") + "]"
        case let .path(p):
            return escapeAndQuote(p.path(percentEncoded: false))
        }
    }

    /// Escapes and quotes a string for JavaScript evaluation.
    ///
    /// Escapes:
    /// - Backslashes: \ → \\
    /// - Double quotes: " → \"
    /// - Newlines: \n → \\n
    /// - Carriage returns: \r → \\r
    /// - Tabs: \t → \\t
    static func escapeAndQuote(_ string: String) -> String {
        let escaped = string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }
}
