import Foundation

/// Long-form CLI flags the macro-accepting `hatch` subcommands claim for
/// themselves.
///
/// `hatch preview` and `hatch direct` collect macro values from *unrecognized*
/// options, so a template macro whose kebab-case flag matches a built-in flag
/// can never be provided on that command line — the built-in flag always wins
/// and the macro reports "not provided" no matter what the user types.
/// `template validate` surfaces such macros as warnings via
/// ``collisionWarnings(for:)``.
///
/// These sets mirror the `@Option`/`@Flag` declarations in
/// `EggCLI/Commands/HatchTransactionCommands.swift` (preview) and
/// `EggCLI/Commands/HatchCommand.swift` (direct). A drift test in
/// `EggCLITests` parses each command's actual help output and fails if either
/// set stops matching the real parser, so the lists can't silently rot.
package enum HatchReservedFlags {
    /// Long flags of `egg hatch preview` (including ArgumentParser's implicit `--help`).
    package static let preview: Set<String> = [
        "help",
        "diff",
        "no-sandbox",
        "user-confirmed-no-sandbox",
        "allow-write",
        "allow-large-staging",
        "allow-non-git-staging",
        "include",
        "exclude",
        "output",
        "project-directory",
        "working-directory",
        "template-search-paths",
    ]

    /// Long flags of `egg hatch direct` (including ArgumentParser's implicit `--help`).
    package static let direct: Set<String> = [
        "help",
        "no-staging",
        "override-conflicts",
        "no-sandbox",
        "apply-changes",
        "project-directory",
        "staging-root",
        "picker",
        "template-search-paths",
    ]

    /// Warning strings for every macro whose CLI flag a hatch subcommand
    /// already claims, empty when all macros are reachable.
    ///
    /// Boolean macros are checked in both spellings (`--flag` for true,
    /// `--no-flag` for false) since either collision makes one of the values
    /// impossible to pass.
    package static func collisionWarnings(for macros: [Config.Macro]) -> [String] {
        var warnings: [String] = []
        for macro in macros {
            let flag = String(MacroNameConverter.macroToFlag(macro.name).dropFirst(2))
            var candidates = [flag]
            if macro.type == .boolean {
                candidates.append("no-\(flag)")
            }
            for candidate in candidates {
                let commands = [("preview", preview), ("direct", direct)]
                    .filter { $0.1.contains(candidate) }
                    .map { "'egg hatch \($0.0)'" }
                guard !commands.isEmpty else { continue }
                warnings.append(
                    "Macro '\(macro.name)' becomes CLI flag '--\(candidate)', which \(commands.joined(separator: " and ")) already claims as a built-in flag — the macro can never be provided on that command line. Rename the macro (e.g. '\(suggestedRename(for: macro.name))').",
                )
            }
        }
        return warnings
    }

    /// A collision-free rename suggestion: append `_VALUE` inside the
    /// trailing underscores (`___OUTPUT___` → `___OUTPUT_VALUE___`).
    private static func suggestedRename(for macroName: String) -> String {
        let inner = macroName.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return "___\(inner)_VALUE___"
    }
}
