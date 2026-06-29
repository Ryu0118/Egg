@testable import EggKit
import Foundation
import Testing

struct PathValidationRuleTests {
    static let workingDirectory = URL(filePath: "/Users/test/projects")
    static let homeDirectory = URL(filePath: "/Users/test")

    @Test(arguments: TestCase.allCases)
    func validate(_ testCase: TestCase) {
        let rule = PathValidationRule(
            workingDirectory: Self.workingDirectory,
            homeDirectory: Self.homeDirectory,
            error: "Invalid path",
        )
        let result = rule.validate(input: testCase.input)
        #expect(result == testCase.expected)
    }

    struct TestCase: CustomTestStringConvertible {
        let description: String
        let input: String
        let expected: Bool

        var testDescription: String {
            description
        }

        static let allCases: [TestCase] = [
            // Valid paths
            TestCase(
                description: "validates absolute path",
                input: "/usr/local/bin",
                expected: true,
            ),
            TestCase(
                description: "validates relative path",
                input: "subdir/file.txt",
                expected: true,
            ),
            TestCase(
                description: "validates current directory",
                input: ".",
                expected: true,
            ),
            TestCase(
                description: "validates tilde expansion",
                input: "~/Documents",
                expected: true,
            ),
            TestCase(
                description: "validates tilde only",
                input: "~",
                expected: true,
            ),
            TestCase(
                description: "validates path with spaces",
                input: "/path/with spaces/file",
                expected: true,
            ),

            // Edge cases
            TestCase(
                description: "rejects empty input",
                input: "",
                expected: false,
            ),
            TestCase(
                description: "whitespace only resolves to working directory",
                input: "   ",
                expected: true,
            ),
        ]
    }
}
