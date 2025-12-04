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
                expected: .success([EggMacro(macro: "NAME", content: "value")])
            ),
            TestCase(
                description: "parses multiple macros with content",
                macros: ["--name", "value1", "--age", "25"],
                expected: .success([
                    EggMacro(macro: "NAME", content: "value1"),
                    EggMacro(macro: "AGE", content: "25")
                ])
            ),
            TestCase(
                description: "normalizes kebab-case macro name to UPPER_SNAKE_CASE",
                macros: ["--my-app-name", "TestApp"],
                expected: .success([EggMacro(macro: "MY_APP_NAME", content: "TestApp")])
            ),
            TestCase(
                description: "normalizes mixed case macro name to uppercase",
                macros: ["--MyMacro", "value"],
                expected: .success([EggMacro(macro: "MYMACRO", content: "value")])
            ),
            TestCase(
                description: "allows content with special characters",
                macros: ["--url", "https://example.com/path?query=value"],
                expected: .success([EggMacro(macro: "URL", content: "https://example.com/path?query=value")])
            ),
            TestCase(
                description: "allows content with spaces",
                macros: ["--message", "Hello World"],
                expected: .success([EggMacro(macro: "MESSAGE", content: "Hello World")])
            ),
            TestCase(
                description: "returns empty array for empty input",
                macros: [],
                expected: .success([])
            ),
            TestCase(
                description: "normalizes underscore in macro name to UPPER_SNAKE_CASE",
                macros: ["--user_defined", "value"],
                expected: .success([EggMacro(macro: "USER_DEFINED", content: "value")])
            ),
            TestCase(
                description: "normalizes mixed underscore and hyphen to UPPER_SNAKE_CASE",
                macros: ["--user-defined_name", "TestValue"],
                expected: .success([EggMacro(macro: "USER_DEFINED_NAME", content: "TestValue")])
            ),
            TestCase(
                description: "normalizes lowercase macro name to uppercase",
                macros: ["--name", "value"],
                expected: .success([EggMacro(macro: "NAME", content: "value")])
            ),
            TestCase(
                description: "keeps uppercase macro name as uppercase",
                macros: ["--NAME", "value"],
                expected: .success([EggMacro(macro: "NAME", content: "value")])
            ),
            TestCase(
                description: "normalizes macro name with numbers",
                macros: ["--name123", "value"],
                expected: .success([EggMacro(macro: "NAME123", content: "value")])
            ),
            TestCase(
                description: "normalizes macro name with hyphen and numbers",
                macros: ["--name-123", "value"],
                expected: .success([EggMacro(macro: "NAME_123", content: "value")])
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
                description: "throws error when content starts with double dash",
                macros: ["--name", "--value"],
                expected: .failure(.contentStartsWithDoubleDash(macro: "--name", content: "--value"))
            ),
            TestCase(
                description: "throws error when consecutive content values are provided",
                macros: ["--name", "value1", "value2"],
                expected: .failure(.consecutiveContentValues(first: "value1", second: "value2"))
            ),
            TestCase(
                description: "throws error when second element starts with single dash (detected as consecutive content)",
                macros: ["--valid", "value", "-invalid", "value2"],
                expected: .failure(.consecutiveContentValues(first: "value", second: "-invalid"))
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
