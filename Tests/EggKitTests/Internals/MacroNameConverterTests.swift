@testable import EggKit
import Testing

struct MacroNameConverterTests {
    // MARK: - flagToMacro Tests

    @Test(arguments: FlagToMacroTestCase.allCases)
    func flagToMacro(_ testCase: FlagToMacroTestCase) {
        let result = MacroNameConverter.flagToMacro(testCase.flag)
        #expect(result == testCase.expected)
    }

    struct FlagToMacroTestCase: CustomTestStringConvertible {
        let description: String
        let flag: String
        let expected: String

        var testDescription: String { description }

        static let allCases: [FlagToMacroTestCase] = [
            FlagToMacroTestCase(
                description: "simple flag",
                flag: "--name",
                expected: "___NAME___"
            ),
            FlagToMacroTestCase(
                description: "kebab-case flag",
                flag: "--app-name",
                expected: "___APP_NAME___"
            ),
            FlagToMacroTestCase(
                description: "multiple dashes",
                flag: "--my-long-macro-name",
                expected: "___MY_LONG_MACRO_NAME___"
            ),
            FlagToMacroTestCase(
                description: "flag without dashes prefix",
                flag: "app-name",
                expected: "___APP_NAME___"
            ),
            FlagToMacroTestCase(
                description: "mixed case flag",
                flag: "--AppName",
                expected: "___APPNAME___"
            ),
            FlagToMacroTestCase(
                description: "flag with numbers",
                flag: "--name-123",
                expected: "___NAME_123___"
            ),
        ]
    }

    // MARK: - macroToFlag Tests

    @Test(arguments: MacroToFlagTestCase.allCases)
    func macroToFlag(_ testCase: MacroToFlagTestCase) {
        let result = MacroNameConverter.macroToFlag(testCase.macro)
        #expect(result == testCase.expected)
    }

    struct MacroToFlagTestCase: CustomTestStringConvertible {
        let description: String
        let macro: String
        let expected: String

        var testDescription: String { description }

        static let allCases: [MacroToFlagTestCase] = [
            MacroToFlagTestCase(
                description: "simple macro",
                macro: "___NAME___",
                expected: "--name"
            ),
            MacroToFlagTestCase(
                description: "snake_case macro",
                macro: "___APP_NAME___",
                expected: "--app-name"
            ),
            MacroToFlagTestCase(
                description: "multiple underscores",
                macro: "___MY_LONG_MACRO_NAME___",
                expected: "--my-long-macro-name"
            ),
            MacroToFlagTestCase(
                description: "mixed case macro",
                macro: "___AppName___",
                expected: "--appname"
            ),
            MacroToFlagTestCase(
                description: "macro with numbers",
                macro: "___NAME_123___",
                expected: "--name-123"
            ),
        ]
    }

    // MARK: - Roundtrip Tests

    @Test(arguments: RoundtripTestCase.allCases)
    func roundtrip(_ testCase: RoundtripTestCase) {
        let macro = MacroNameConverter.flagToMacro(testCase.flag)
        let backToFlag = MacroNameConverter.macroToFlag(macro)
        #expect(backToFlag == testCase.expectedFlag)
    }

    struct RoundtripTestCase: CustomTestStringConvertible {
        let description: String
        let flag: String
        let expectedFlag: String

        var testDescription: String { description }

        static let allCases: [RoundtripTestCase] = [
            RoundtripTestCase(
                description: "simple flag roundtrip",
                flag: "--name",
                expectedFlag: "--name"
            ),
            RoundtripTestCase(
                description: "kebab-case flag roundtrip",
                flag: "--app-name",
                expectedFlag: "--app-name"
            ),
            RoundtripTestCase(
                description: "long kebab-case roundtrip",
                flag: "--my-long-macro-name",
                expectedFlag: "--my-long-macro-name"
            ),
        ]
    }
}
