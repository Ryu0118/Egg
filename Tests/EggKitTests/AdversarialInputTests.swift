@testable import EggKit
import Foundation
import Testing
import Yams

/// Hostile-input hardening: parsers must either return or throw their own
/// typed errors — never crash, hang, or fall into unrelated failures.
@Suite("Adversarial inputs never crash the parsers")
struct AdversarialInputTests {
    // MARK: - MacrosParser property test

    /// A deterministic linear-congruential generator so failures reproduce.
    private struct SplitMix64: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    private static let hostileTokens: [String] = [
        "--name", "--flag", "--no-flag", "--choice", "value", "true", "false",
        "", "-", "--", "-x", "--=", "--name=value", "a=b",
        "🥚", "--🥚", "日本語", "--日本語",
        "\u{0000}", "\u{0001}\u{0002}", "\n", "\t",
        String(repeating: "x", count: 5000),
        "--" + String(repeating: "N", count: 2000),
        "../../etc/passwd", "--../escape", "$(rm -rf /)", "`id`", "; echo pwned",
    ]

    @Test("MacrosParser survives 2000 randomized hostile argument arrays")
    func macrosParserSurvivesRandomizedHostileArguments() {
        let definitions = [
            Config.Macro(name: "___NAME___", description: "n", type: .string),
            Config.Macro(name: "___FLAG___", description: "f", type: .boolean),
            Config.Macro(name: "___CHOICE___", description: "c", type: .choice, choices: ["a", "b"]),
            Config.Macro(name: "___ITEMS___", description: "i", type: .array),
        ]
        let parser = MacrosParser(macroDefinitions: definitions)
        var generator = SplitMix64(state: 0xE990001)

        for _ in 0 ..< 2000 {
            let length = Int.random(in: 0 ... 8, using: &generator)
            let arguments = (0 ..< length).map { _ in
                Self.hostileTokens.randomElement(using: &generator)!
            }
            // The property: returns or throws MacrosParseError — anything
            // else (crash, unrelated error type) fails the test run itself.
            do {
                _ = try parser.parseCommandLineArguments(arguments)
            } catch is MacrosParseError {
                // expected failure mode
            } catch {
                Issue.record("Unexpected error type \(type(of: error)) for arguments \(arguments): \(error)")
            }
        }
    }

    // MARK: - Config decoding fuzz corpus

    private static let hostileYAML: [String] = [
        "",
        "   ",
        "name: [unclosed",
        "\u{0000}\u{0001}",
        "name: A\ndescription: d\nhatch:\n  output: .\nmacros: notalist",
        "name: A\ndescription: d\nhatch: []",
        "name: A\ndescription: d\nhatch:\n  output: 42",
        "name: {a: {b: {c: {d: {e: {f: {g: {h: {i: {j: 1}}}}}}}}}}",
        // Anchor expansion (mini billion-laughs; must stay bounded).
        "a: &a [1,2]\nb: &b [*a,*a]\nc: &c [*b,*b]\nd: [*c,*c]\nname: A\ndescription: d\nhatch:\n  output: .",
        "name: " + String(repeating: "A", count: 200_000) + "\ndescription: d\nhatch:\n  output: .",
        "name: A\ndescription: d\nhatch:\n  output: .\nmacros:\n  - name: 日本語\n    description: d",
        "name: A\ndescription: d\nhatch:\n  output: .\nmacros:\n  - name: ___OK___\n    description: d\n    type: nonsense",
        "name: !!binary Zm9v\ndescription: d\nhatch:\n  output: .",
        "--- !!map\n? name\n: A",
    ]

    @Test("Config decoding returns or throws for every hostile YAML document", arguments: Self.hostileYAML.indices)
    func configDecodingSurvivesHostileYAML(_ index: Int) {
        let yaml = Self.hostileYAML[index]
        // Returns a Config or throws — the property under test is the absence
        // of crashes/hangs, so any thrown error is acceptable here.
        _ = try? YAMLDecoder().decode(Config.self, from: yaml)
    }

    // MARK: - Unknown-key scanner

    @Test("The scanner names silently-ignored keys at every nesting level")
    func scannerNamesSilentlyIgnoredKeys() {
        let yaml = """
        name: T
        description: d
        lifecycle:
          post_hatch:
            - run: echo never runs
        macros:
          - name: ___A___
            description: a
            defalt: oops
        pre_hatch:
          - id: s
            run: echo hi
            when: typo
        sandbox:
          allowed_path: singular-typo
        hatch:
          output: .
          excludes: plural-typo
          exclude:
            - if: "true"
              paths: [a.txt]
              pattern: extra
        """
        let warnings = ConfigUnknownKeyScanner().unknownKeyWarnings(inYAML: yaml)

        #expect(warnings.contains { $0.contains("'lifecycle'") && $0.contains("top-level") })
        #expect(warnings.contains { $0.contains("'defalt'") && $0.contains("___A___") })
        #expect(warnings.contains { $0.contains("'when'") && $0.contains("pre_hatch[0]") })
        #expect(warnings.contains { $0.contains("'allowed_path'") && $0.contains("sandbox") })
        #expect(warnings.contains { $0.contains("'excludes'") && $0.contains("hatch") })
        #expect(warnings.contains { $0.contains("'pattern'") && $0.contains("hatch.exclude[0]") })
    }

    @Test("A clean config yields no unknown-key warnings")
    func cleanConfigYieldsNoWarnings() {
        let yaml = """
        name: T
        description: d
        version: "1.0"
        macros:
          - name: ___A___
            description: a
            type: choice
            default: x
            choices: [x, y]
        sandbox:
          allowed_paths: [/tmp/x]
        pre_hatch:
          - id: s
            if: "true"
            run: echo hi
        hatch:
          output: .
          exclude:
            - "*.log"
            - if: "true"
              paths: [a.txt]
        post_hatch:
          - run: echo done
        """
        #expect(ConfigUnknownKeyScanner().unknownKeyWarnings(inYAML: yaml).isEmpty)
    }

    @Test("Unparseable YAML yields no scanner warnings — the decoder already fails loudly")
    func unparseableYAMLYieldsNoScannerWarnings() {
        #expect(ConfigUnknownKeyScanner().unknownKeyWarnings(inYAML: "name: [unclosed").isEmpty)
    }
}
