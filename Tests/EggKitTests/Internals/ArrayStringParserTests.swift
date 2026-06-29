@testable import EggKit
import Testing

struct ArrayStringParserTests {
    // MARK: - isValidArrayString Tests

    @Test(arguments: IsValidArrayStringTestCase.allCases)
    func `is valid array string`(_ testCase: IsValidArrayStringTestCase) {
        let result = ArrayStringParser.isValidArrayString(testCase.input)
        #expect(result == testCase.expected)
    }

    struct IsValidArrayStringTestCase: CustomTestStringConvertible {
        let description: String
        let input: String
        let expected: Bool

        var testDescription: String {
            description
        }

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

        var testDescription: String {
            description
        }

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
    }

    // MARK: - toSpaceSeparated Tests

    @Test(arguments: ToSpaceSeparatedTestCase.allCases)
    func `to space separated`(_ testCase: ToSpaceSeparatedTestCase) {
        let result = ArrayStringParser.toSpaceSeparated(testCase.input)
        #expect(result == testCase.expected)
    }

    struct ToSpaceSeparatedTestCase: CustomTestStringConvertible {
        let description: String
        let input: String
        let expected: String

        var testDescription: String {
            description
        }

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
    }
}
