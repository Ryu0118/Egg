import Foundation
import RegexBuilder

enum Regexes {
    /// Matches macro references like ___NAME___
    static var macroReference: Regex<(Substring, Substring)> {
        Regex {
            "___"
            Capture {
                OneOrMore {
                    ChoiceOf {
                        CharacterClass("A" ... "Z")
                        CharacterClass("0" ... "9")
                        "_"
                    }
                }
            }
            "___"
        }
    }

    /// Matches GitHub Actions–style step output references: ${{ ... }}
    static var stepOutput: Regex<(Substring, Substring)> {
        Regex {
            "${{"
            ZeroOrMore(.whitespace)
            Capture {
                OneOrMore {
                    NegativeLookahead {
                        "}}"
                    }
                    CharacterClass.any
                }
            }
            ZeroOrMore(.whitespace)
            "}}"
        }
    }

    /// Matches step output references with phase, step ID, and key:
    /// ${{ phase.step-id.outputs.key }}
    static var stepOutputDetailed: Regex<(Substring, Substring, Substring, Substring)> {
        Regex {
            "${{"
            ZeroOrMore(.whitespace)
            // Capture 1: phase (e.g., pre_hatch, post_hatch)
            Capture {
                OneOrMore(.word)
            }
            "."
            // Capture 2: step-id (alphanumeric, hyphens, underscores)
            Capture {
                OneOrMore {
                    ChoiceOf {
                        CharacterClass("a" ... "z")
                        CharacterClass("A" ... "Z")
                        CharacterClass("0" ... "9")
                        "_"
                        "-"
                    }
                }
            }
            ".outputs."
            // Capture 3: key (alphanumeric, hyphens, underscores, dots)
            Capture {
                OneOrMore {
                    ChoiceOf {
                        CharacterClass("a" ... "z")
                        CharacterClass("A" ... "Z")
                        CharacterClass("0" ... "9")
                        "_"
                        "-"
                        "."
                    }
                }
            }
            ZeroOrMore(.whitespace)
            "}}"
        }
    }
}
