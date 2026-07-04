@testable import EggKit
import Testing

struct ArrayStringParserTests {
    // MARK: - isValidArrayString Tests

    @Test("detects whether a string is well-formed JSON array syntax versus plain text", arguments: IsValidArrayStringTestCase.allCases)
    func isValidArrayString(_ testCase: IsValidArrayStringTestCase) {
        let result = ArrayStringParser.isValidArrayString(testCase.input)
        #expect(result == testCase.expected)
    }

    struct IsValidArrayStringTestCase: CustomTestStringConvertible {
        let description: String
        let input: String
        let expected: Bool

        static let allCases: [IsValidArrayStringTestCase] = [
            IsValidArrayStringTestCase(
                description: "valid JSON array",
                input: "[\"iOS\",\"macOS\"]",
                expected: true,
            ),
            IsValidArrayStringTestCase(
                description: "valid JSON array with spaces",
                input: " [\"iOS\",\"macOS\"] ",
                expected: true,
            ),
            IsValidArrayStringTestCase(
                description: "empty array",
                input: "[]",
                expected: true,
            ),
            IsValidArrayStringTestCase(
                description: "not an array - plain string",
                input: "iOS macOS",
                expected: false,
            ),
            IsValidArrayStringTestCase(
                description: "not an array - missing closing bracket",
                input: "[iOS",
                expected: false,
            ),
            IsValidArrayStringTestCase(
                description: "not an array - missing opening bracket",
                input: "iOS]",
                expected: false,
            ),
        ]

        var testDescription: String {
            description
        }
    }

    // MARK: - parse Tests

    @Test(arguments: ParseTestCase.allCases)
    func parse(_ testCase: ParseTestCase) {
        let result = ArrayStringParser.parse(testCase.input)
        #expect(result == testCase.expected)
    }

    struct ParseTestCase: CustomTestStringConvertible {
        let description: String
        let input: String
        let expected: [String]

        static let allCases: [ParseTestCase] = [
            ParseTestCase(
                description: "parses JSON array",
                input: "[\"iOS\",\"macOS\",\"tvOS\"]",
                expected: ["iOS", "macOS", "tvOS"],
            ),
            ParseTestCase(
                description: "parses JSON array with spaces",
                input: "[\"iOS\", \"macOS\", \"tvOS\"]",
                expected: ["iOS", "macOS", "tvOS"],
            ),
            ParseTestCase(
                description: "parses empty array",
                input: "[]",
                expected: [],
            ),
            ParseTestCase(
                description: "parses single element",
                input: "[\"iOS\"]",
                expected: ["iOS"],
            ),
            ParseTestCase(
                description: "returns empty for non-array string",
                input: "iOS macOS",
                expected: [],
            ),
            ParseTestCase(
                description: "parses array with trimmed whitespace",
                input: " [\"iOS\",\"macOS\"] ",
                expected: ["iOS", "macOS"],
            ),
        ]

        var testDescription: String {
            description
        }
    }

    // MARK: - toSpaceSeparated Tests

    @Test("converts a JSON array string into a space-separated string, leaving non-array input unchanged", arguments: ToSpaceSeparatedTestCase.allCases)
    func toSpaceSeparated(_ testCase: ToSpaceSeparatedTestCase) {
        let result = ArrayStringParser.toSpaceSeparated(testCase.input)
        #expect(result == testCase.expected)
    }

    struct ToSpaceSeparatedTestCase: CustomTestStringConvertible {
        let description: String
        let input: String
        let expected: String

        static let allCases: [ToSpaceSeparatedTestCase] = [
            ToSpaceSeparatedTestCase(
                description: "converts JSON array to space-separated",
                input: "[\"iOS\",\"macOS\",\"tvOS\"]",
                expected: "iOS macOS tvOS",
            ),
            ToSpaceSeparatedTestCase(
                description: "returns original for non-array string",
                input: "iOS macOS",
                expected: "iOS macOS",
            ),
            ToSpaceSeparatedTestCase(
                description: "converts single element array",
                input: "[\"iOS\"]",
                expected: "iOS",
            ),
            ToSpaceSeparatedTestCase(
                description: "converts empty array to empty string",
                input: "[]",
                expected: "",
            ),
        ]

        var testDescription: String {
            description
        }
    }
}
