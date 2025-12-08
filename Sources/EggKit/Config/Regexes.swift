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
}
