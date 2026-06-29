@testable import EggKit
import Foundation
import Testing

struct MacrosParserTests {
    @Test(arguments: TestCase.allCases)
    func `parse command line arguments`(_ testCase: TestCase) throws {
        let parser = MacrosParser(macroDefinitions: testCase.macroDefinitions)
        switch testCase.expected {
        case let .success(expectedMacros):
            let result = try parser.parseCommandLineArguments(testCase.macros)
            #expect(result == expectedMacros)
        case let .failure(expectedError):
            #expect(throws: expectedError) {
                _ = try parser.parseCommandLineArguments(testCase.macros)
            }
        }
    }

    struct TestCase: CustomTestStringConvertible {
        let description: String
        let macros: [String]
        let macroDefinitions: [Config.Macro]
        let expected: Result

        var testDescription: String {
            description
        }

        init(
            description: String,
            macros: [String],
            macroDefinitions: [Config.Macro] = [],
            expected: Result,
        ) {
            self.description = description
            self.macros = macros
            self.macroDefinitions = macroDefinitions
            self.expected = expected
        }

        static let allCases: [TestCase] = [
            TestCase(
                description: "parses single macro with content",
                macros: ["--name", "value"],
                expected: .success([ParsedMacroDefinition(macro: "___NAME___", values: ["value"])]),
            ),
            TestCase(
                description: "parses multiple macros with content",
                macros: ["--name", "value1", "--age", "25"],
                expected: .success([
                    ParsedMacroDefinition(macro: "___NAME___", values: ["value1"]),
                    ParsedMacroDefinition(macro: "___AGE___", values: ["25"]),
                ]),
            ),
            TestCase(
                description: "parses array macro with multiple values",
                macros: ["--platforms", "iOS", "macOS", "watchOS"],
                expected: .success([ParsedMacroDefinition(macro: "___PLATFORMS___", values: ["iOS", "macOS", "watchOS"])]),
            ),
            TestCase(
                description: "parses single macro with multiple consecutive values",
                macros: ["--name", "value1", "value2"],
                expected: .success([ParsedMacroDefinition(macro: "___NAME___", values: ["value1", "value2"])]),
            ),
            TestCase(
                description: "parses multiple macros where first is array",
                macros: ["--platforms", "iOS", "macOS", "--name", "MyApp"],
                expected: .success([
                    ParsedMacroDefinition(macro: "___PLATFORMS___", values: ["iOS", "macOS"]),
                    ParsedMacroDefinition(macro: "___NAME___", values: ["MyApp"]),
                ]),
            ),
            TestCase(
                description: "normalizes kebab-case macro name to UPPER_SNAKE_CASE",
                macros: ["--my-app-name", "TestApp"],
                expected: .success([ParsedMacroDefinition(macro: "___MY_APP_NAME___", values: ["TestApp"])]),
            ),
            TestCase(
                description: "normalizes mixed case macro name to uppercase",
                macros: ["--MyMacro", "value"],
                expected: .success([ParsedMacroDefinition(macro: "___MYMACRO___", values: ["value"])]),
            ),
            TestCase(
                description: "allows content with special characters",
                macros: ["--url", "https://example.com/path?query=value"],
                expected: .success([ParsedMacroDefinition(macro: "___URL___", values: ["https://example.com/path?query=value"])]),
            ),
            TestCase(
                description: "allows content with spaces",
                macros: ["--message", "Hello World"],
                expected: .success([ParsedMacroDefinition(macro: "___MESSAGE___", values: ["Hello World"])]),
            ),
            TestCase(
                description: "returns empty array for empty input",
                macros: [],
                expected: .success([]),
            ),
            TestCase(
                description: "normalizes underscore in macro name to UPPER_SNAKE_CASE",
                macros: ["--user_defined", "value"],
                expected: .success([ParsedMacroDefinition(macro: "___USER_DEFINED___", values: ["value"])]),
            ),
            TestCase(
                description: "normalizes mixed underscore and hyphen to UPPER_SNAKE_CASE",
                macros: ["--user-defined_name", "TestValue"],
                expected: .success([ParsedMacroDefinition(macro: "___USER_DEFINED_NAME___", values: ["TestValue"])]),
            ),
            TestCase(
                description: "normalizes lowercase macro name to uppercase",
                macros: ["--name", "value"],
                expected: .success([ParsedMacroDefinition(macro: "___NAME___", values: ["value"])]),
            ),
            TestCase(
                description: "keeps uppercase macro name as uppercase",
                macros: ["--NAME", "value"],
                expected: .success([ParsedMacroDefinition(macro: "___NAME___", values: ["value"])]),
            ),
            TestCase(
                description: "normalizes macro name with numbers",
                macros: ["--name123", "value"],
                expected: .success([ParsedMacroDefinition(macro: "___NAME123___", values: ["value"])]),
            ),
            TestCase(
                description: "normalizes macro name with hyphen and numbers",
                macros: ["--name-123", "value"],
                expected: .success([ParsedMacroDefinition(macro: "___NAME_123___", values: ["value"])]),
            ),
            TestCase(
                description: "throws error when macro starts with single dash",
                macros: ["-name", "value"],
                expected: .failure(.singleDashNotAllowed(macro: "-name")),
            ),
            TestCase(
                description: "throws error when macro missing double dash",
                macros: ["name", "value"],
                expected: .failure(.missingDoubleDash(macro: "name")),
            ),
            TestCase(
                description: "throws error when macro name is empty",
                macros: ["--", "value"],
                expected: .failure(.emptyMacroName),
            ),
            TestCase(
                description: "throws error when content is missing",
                macros: ["--name"],
                expected: .failure(.missingContent(macro: "--name")),
            ),
            TestCase(
                description: "throws error when value starts with single dash",
                macros: ["--name", "-invalid"],
                expected: .failure(.singleDashNotAllowed(macro: "-invalid")),
            ),
            TestCase(
                description: "throws error when macro starts with single dash (first position)",
                macros: ["-invalid", "value"],
                expected: .failure(.singleDashNotAllowed(macro: "-invalid")),
            ),
            TestCase(
                description: "throws error on last macro when content is missing",
                macros: ["--first", "value1", "--second"],
                expected: .failure(.missingContent(macro: "--second")),
            ),
            // Boolean macro tests
            TestCase(
                description: "parses boolean macro --flag as true",
                macros: ["--create-tests"],
                macroDefinitions: [
                    Config.Macro(name: "___CREATE_TESTS___", description: "Create tests", type: .boolean),
                ],
                expected: .success([ParsedMacroDefinition(macro: "___CREATE_TESTS___", values: ["true"])]),
            ),
            TestCase(
                description: "parses boolean macro --no-flag as false",
                macros: ["--no-create-tests"],
                macroDefinitions: [
                    Config.Macro(name: "___CREATE_TESTS___", description: "Create tests", type: .boolean),
                ],
                expected: .success([ParsedMacroDefinition(macro: "___CREATE_TESTS___", values: ["false"])]),
            ),
            TestCase(
                description: "parses multiple boolean macros",
                macros: ["--create-tests", "--no-include-docs"],
                macroDefinitions: [
                    Config.Macro(name: "___CREATE_TESTS___", description: "Create tests", type: .boolean),
                    Config.Macro(name: "___INCLUDE_DOCS___", description: "Include docs", type: .boolean),
                ],
                expected: .success([
                    ParsedMacroDefinition(macro: "___CREATE_TESTS___", values: ["true"]),
                    ParsedMacroDefinition(macro: "___INCLUDE_DOCS___", values: ["false"]),
                ]),
            ),
            TestCase(
                description: "parses mixed boolean and string macros",
                macros: ["--name", "MyApp", "--create-tests", "--version", "1.0"],
                macroDefinitions: [
                    Config.Macro(name: "___CREATE_TESTS___", description: "Create tests", type: .boolean),
                ],
                expected: .success([
                    ParsedMacroDefinition(macro: "___NAME___", values: ["MyApp"]),
                    ParsedMacroDefinition(macro: "___CREATE_TESTS___", values: ["true"]),
                    ParsedMacroDefinition(macro: "___VERSION___", values: ["1.0"]),
                ]),
            ),
            // Edge case: --no-xxx where ___NO_XXX___ is a non-boolean macro (not negation)
            TestCase(
                description: "parses --notify as ___NOTIFY___ string macro (not negation)",
                macros: ["--notify", "email"],
                macroDefinitions: [
                    Config.Macro(name: "___NOTIFY___", description: "Notification method", type: .string),
                ],
                expected: .success([ParsedMacroDefinition(macro: "___NOTIFY___", values: ["email"])]),
            ),
            TestCase(
                description: "parses --no-cache as ___NO_CACHE___ string macro when defined",
                macros: ["--no-cache", "true"],
                macroDefinitions: [
                    Config.Macro(name: "___NO_CACHE___", description: "Disable cache", type: .string),
                ],
                expected: .success([ParsedMacroDefinition(macro: "___NO_CACHE___", values: ["true"])]),
            ),
            TestCase(
                description: "parses --no-cache as ___CACHE___ boolean false when CACHE is boolean",
                macros: ["--no-cache"],
                macroDefinitions: [
                    Config.Macro(name: "___CACHE___", description: "Enable cache", type: .boolean),
                ],
                expected: .success([ParsedMacroDefinition(macro: "___CACHE___", values: ["false"])]),
            ),
        ]

        enum Result {
            case success([ParsedMacroDefinition])
            case failure(MacrosParseError)
        }
    }
}
