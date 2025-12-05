import Foundation
import Testing
@testable import EggKit

struct EggMacrosParserTests {
    let parser = EggMacrosParser()

    @Test(arguments: TestCase.allCases)
    func parse(_ testCase: TestCase) throws {
        switch testCase.expected {
        case .success(let expectedMacros):
            let result = try parser.parse(testCase.macros)
            #expect(result == expectedMacros)
        case .failure(let expectedError):
            #expect(throws: expectedError) {
                _ = try parser.parse(testCase.macros)
            }
        }
    }

    struct TestCase: CustomTestStringConvertible {
        let description: String
        let macros: [String]
        let expected: Result

        var testDescription: String { description }

        static let allCases: [TestCase] = [
            // Success cases
            TestCase(
                description: "parses single macro with content",
                macros: ["--name", "value"],
                expected: .success([EggMacro(macro: "NAME", values: ["value"])])
            ),
            TestCase(
                description: "parses multiple macros with content",
                macros: ["--name", "value1", "--age", "25"],
                expected: .success([
                    EggMacro(macro: "NAME", values: ["value1"]),
                    EggMacro(macro: "AGE", values: ["25"])
                ])
            ),
            TestCase(
                description: "parses array macro with multiple values",
                macros: ["--platforms", "iOS", "macOS", "watchOS"],
                expected: .success([EggMacro(macro: "PLATFORMS", values: ["iOS", "macOS", "watchOS"])])
            ),
            TestCase(
                description: "parses single macro with multiple consecutive values",
                macros: ["--name", "value1", "value2"],
                expected: .success([EggMacro(macro: "NAME", values: ["value1", "value2"])])
            ),
            TestCase(
                description: "parses multiple macros where first is array",
                macros: ["--platforms", "iOS", "macOS", "--name", "MyApp"],
                expected: .success([
                    EggMacro(macro: "PLATFORMS", values: ["iOS", "macOS"]),
                    EggMacro(macro: "NAME", values: ["MyApp"])
                ])
            ),
            TestCase(
                description: "normalizes kebab-case macro name to UPPER_SNAKE_CASE",
                macros: ["--my-app-name", "TestApp"],
                expected: .success([EggMacro(macro: "MY_APP_NAME", values: ["TestApp"])])
            ),
            TestCase(
                description: "normalizes mixed case macro name to uppercase",
                macros: ["--MyMacro", "value"],
                expected: .success([EggMacro(macro: "MYMACRO", values: ["value"])])
            ),
            TestCase(
                description: "allows content with special characters",
                macros: ["--url", "https://example.com/path?query=value"],
                expected: .success([EggMacro(macro: "URL", values: ["https://example.com/path?query=value"])])
            ),
            TestCase(
                description: "allows content with spaces",
                macros: ["--message", "Hello World"],
                expected: .success([EggMacro(macro: "MESSAGE", values: ["Hello World"])])
            ),
            TestCase(
                description: "returns empty array for empty input",
                macros: [],
                expected: .success([])
            ),
            TestCase(
                description: "normalizes underscore in macro name to UPPER_SNAKE_CASE",
                macros: ["--user_defined", "value"],
                expected: .success([EggMacro(macro: "USER_DEFINED", values: ["value"])])
            ),
            TestCase(
                description: "normalizes mixed underscore and hyphen to UPPER_SNAKE_CASE",
                macros: ["--user-defined_name", "TestValue"],
                expected: .success([EggMacro(macro: "USER_DEFINED_NAME", values: ["TestValue"])])
            ),
            TestCase(
                description: "normalizes lowercase macro name to uppercase",
                macros: ["--name", "value"],
                expected: .success([EggMacro(macro: "NAME", values: ["value"])])
            ),
            TestCase(
                description: "keeps uppercase macro name as uppercase",
                macros: ["--NAME", "value"],
                expected: .success([EggMacro(macro: "NAME", values: ["value"])])
            ),
            TestCase(
                description: "normalizes macro name with numbers",
                macros: ["--name123", "value"],
                expected: .success([EggMacro(macro: "NAME123", values: ["value"])])
            ),
            TestCase(
                description: "normalizes macro name with hyphen and numbers",
                macros: ["--name-123", "value"],
                expected: .success([EggMacro(macro: "NAME_123", values: ["value"])])
            ),

            // Error cases
            TestCase(
                description: "throws error when macro starts with single dash",
                macros: ["-name", "value"],
                expected: .failure(.singleDashNotAllowed(macro: "-name"))
            ),
            TestCase(
                description: "throws error when macro missing double dash",
                macros: ["name", "value"],
                expected: .failure(.missingDoubleDash(macro: "name"))
            ),
            TestCase(
                description: "throws error when macro name is empty",
                macros: ["--", "value"],
                expected: .failure(.emptyMacroName)
            ),
            TestCase(
                description: "throws error when content is missing",
                macros: ["--name"],
                expected: .failure(.missingContent(macro: "--name"))
            ),
            TestCase(
                description: "throws error when value starts with single dash",
                macros: ["--name", "-invalid"],
                expected: .failure(.singleDashNotAllowed(macro: "-invalid"))
            ),
            TestCase(
                description: "throws error when macro starts with single dash (first position)",
                macros: ["-invalid", "value"],
                expected: .failure(.singleDashNotAllowed(macro: "-invalid"))
            ),
            TestCase(
                description: "throws error on last macro when content is missing",
                macros: ["--first", "value1", "--second"],
                expected: .failure(.missingContent(macro: "--second"))
            )
        ]

        enum Result {
            case success([EggMacro])
            case failure(MacrosParseError)
        }
    }
}
