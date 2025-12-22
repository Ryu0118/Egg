import Foundation

/// Bidirectional converter between macro names (`___HOGE___`) and CLI flags (`--hoge`)
enum MacroNameConverter {
    /// Converts CLI flag to macro name
    /// e.g., `--my-app-name` → `___MY_APP_NAME___`
    static func flagToMacro(_ flag: String) -> String {
        var name = flag
        // Remove leading dashes
        while name.hasPrefix("-") {
            name.removeFirst()
        }
        let normalized = name
            .replacingOccurrences(of: "-", with: "_")
            .uppercased()
        return "___\(normalized)___"
    }

    /// Converts macro name to CLI flag
    /// e.g., `___MY_APP_NAME___` → `--my-app-name`
    static func macroToFlag(_ macroName: String) -> String {
        var name = macroName
        // Remove surrounding underscores
        while name.hasPrefix("_") {
            name.removeFirst()
        }
        while name.hasSuffix("_") {
            name.removeLast()
        }
        let flagName = name.lowercased().replacingOccurrences(of: "_", with: "-")
        return "--\(flagName)"
    }
}
