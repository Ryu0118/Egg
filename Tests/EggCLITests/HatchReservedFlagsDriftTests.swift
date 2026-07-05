@testable import EggCLI
import EggKit
import Testing

/// Keeps `HatchReservedFlags` honest: the sets live in EggKit (the validator
/// needs them) while the actual flags are `@Option`/`@Flag` declarations in
/// EggCLI. These tests parse each command's real help output, so adding or
/// removing a flag on either side fails here instead of silently drifting.
@Suite("HatchReservedFlags tracks the real hatch CLI flags")
struct HatchReservedFlagsDriftTests {
    @Test("preview's declared long flags exactly match HatchReservedFlags.preview")
    func previewFlagsMatch() {
        #expect(longFlags(inHelpOf: HatchPreviewCommand.helpMessage(columns: 500)) == HatchReservedFlags.preview)
    }

    @Test("direct's declared long flags exactly match HatchReservedFlags.direct")
    func directFlagsMatch() {
        #expect(longFlags(inHelpOf: HatchDirectCommand.helpMessage(columns: 500)) == HatchReservedFlags.direct)
    }

    /// Long flag names declared in the OPTIONS section of an ArgumentParser
    /// help message. Only the flag-name column is scanned (the text before
    /// the two-space gap separating names from help text), so flags mentioned
    /// inside help strings or the DISCUSSION section don't leak in. The wide
    /// `columns` at the call sites keeps each option on one line so a wrapped
    /// help string can't start a line with `--`.
    private func longFlags(inHelpOf help: String) -> Set<String> {
        guard let optionsRange = help.range(of: "OPTIONS:") else { return [] }
        var flags: Set<String> = []
        for line in help[optionsRange.upperBound...].split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("-") else { continue }
            let namesColumn = trimmed.components(separatedBy: "  ").first ?? trimmed
            for match in namesColumn.matches(of: /--([a-z0-9-]+)/) {
                flags.insert(String(match.1))
            }
        }
        return flags
    }
}
