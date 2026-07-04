@testable import EggKit
import Testing

struct ArrayInputParserTests {
    private let parser = ArrayInputParser()

    @Test("parse from CLI", arguments: CLITestCase.allCases)
    func parseFromCLI(_ testCase: CLITestCase) {
        let result = parser.parseFromCLI(testCase.input)
        #expect(result == testCase.expected)
    }

    struct CLITestCase: CustomTestStringConvertible {
        let description: String
        let input: [String]
        let expected: [String]

        static let allCases: [CLITestCase] = [
            CLITestCase(
                description: "parses space-separated values",
                input: ["iOS", "macOS", "watchOS"],
                expected: ["iOS", "macOS", "watchOS"],
            ),
            CLITestCase(
                description: "splits comma-separated single value",
                input: ["iOS,macOS,watchOS"],
                expected: ["iOS", "macOS", "watchOS"],
            ),
            CLITestCase(
                description: "normalizes mixed separators",
                input: ["iOS,macOS", "watchOS"],
                expected: ["iOS", "macOS", "watchOS"],
            ),
            CLITestCase(
                description: "returns empty array for empty input",
                input: [],
                expected: [],
            ),
        ]

        var testDescription: String {
            description
        }
    }

    @Test("parse from interactive", arguments: InteractiveTestCase.allCases)
    func parseFromInteractive(_ testCase: InteractiveTestCase) {
        let result = parser.parseFromInteractive(testCase.input)
        #expect(result == testCase.expected)
    }

    struct InteractiveTestCase: CustomTestStringConvertible {
        let description: String
        let input: String
        let expected: [String]

        static let allCases: [InteractiveTestCase] = [
            InteractiveTestCase(
                description: "parses comma-separated input",
                input: "iOS, macOS, watchOS",
                expected: ["iOS", "macOS", "watchOS"],
            ),
            InteractiveTestCase(
                description: "trims whitespace from values",
                input: "  iOS  ,  macOS  ",
                expected: ["iOS", "macOS"],
            ),
            InteractiveTestCase(
                description: "filters empty segments",
                input: "iOS,,macOS,",
                expected: ["iOS", "macOS"],
            ),
            InteractiveTestCase(
                description: "returns empty array for empty input",
                input: "",
                expected: [],
            ),
        ]

        var testDescription: String {
            description
        }
    }
}
