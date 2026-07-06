@testable import EggKit
import Testing

/// Proves the scanner's known-key sets are derived from `Config`'s own
/// `CodingKeys`, not a hand-maintained copy that can drift from the schema.
@Suite("ConfigUnknownKeyScanner known-key sets track Config.CodingKeys")
struct ConfigUnknownKeyScannerTests {
    @Test("A key present in Config.CodingKeys but absent from the YAML is never reported")
    func everyCodingKeyIsAcceptedAtEachLevel() {
        // One representative key from every CodingKeys enum the scanner reads.
        // If any of these were hardcoded and out of sync with Config.swift,
        // this would flag a false "unknown key" for a perfectly valid field.
        let yaml = """
        name: T
        description: d
        version: "1.0"
        macros:
          - name: ___A___
            description: a
            type: string
            default: x
            validate: ".*"
            choices: []
        sandbox:
          allowed_paths: [/tmp/x]
        pre_hatch:
          - id: s
            if: "true"
            run: echo hi
        hatch:
          output: .
          exclude:
            - if: "true"
              paths: [a.txt]
        post_hatch:
          - id: p
            if: "true"
            run: echo done
        """
        #expect(ConfigUnknownKeyScanner().unknownKeyWarnings(inYAML: yaml).isEmpty)
    }

    @Test("an unquoted leading '!' in an if condition is flagged as a swallowed condition")
    func unquotedBangConditionIsFlagged() {
        let yaml = """
        name: T
        description: d
        pre_hatch:
          - if: !___X___
            run: echo hi
        hatch:
          output: .
        """
        let warnings = ConfigUnknownKeyScanner().swallowedConditionWarnings(inYAML: yaml)
        #expect(warnings.count == 1)
        #expect(warnings[0].contains("pre_hatch[0]"))
        #expect(warnings[0].contains("quote it"))
    }

    @Test("a quoted '!' condition and an absent if produce no swallowed-condition warning")
    func quotedBangAndAbsentIfAreClean() {
        let yaml = """
        name: T
        description: d
        pre_hatch:
          - if: "!___X___"
            run: echo hi
          - run: echo unconditional
        hatch:
          output: .
        """
        #expect(ConfigUnknownKeyScanner().swallowedConditionWarnings(inYAML: yaml).isEmpty)
    }

    @Test("Every Config.CodingKeys case name round-trips as an accepted top-level key")
    func topLevelCodingKeysAreAllAccepted() {
        for key in Config.CodingKeys.allCases {
            let yaml = "name: T\ndescription: d\nhatch:\n  output: .\n\(key.stringValue): {}"
            let warnings = ConfigUnknownKeyScanner().unknownKeyWarnings(inYAML: yaml)
            #expect(
                !warnings.contains { $0.contains("Unknown top-level key '\(key.stringValue)'") },
                "Config.CodingKeys.\(key) must not be flagged as unknown",
            )
        }
    }
}
