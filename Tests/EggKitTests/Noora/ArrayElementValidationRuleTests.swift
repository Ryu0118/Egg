@testable import EggKit
import Testing

struct ArrayElementValidationRuleTests {
    @Test(arguments: TestCase.allCases)
    func validate(_ testCase: TestCase) {
        let rule = ArrayElementValidationRule(
            elementPattern: testCase.pattern,
            error: "Test error"
        )
        let result = rule.validate(input: testCase.input)
        #expect(result == testCase.expected)
    }

    struct TestCase: CustomTestStringConvertible {
        let description: String
        let pattern: String
        let input: String
        let expected: Bool

        var testDescription: String { description }

        static let allCases: [TestCase] = [
            TestCase(
                description: "validates all elements match pattern",
                pattern: "^[A-Z][a-zA-Z0-9]*$",
                input: "ModuleA, ModuleB, ModuleC",
                expected: true
            ),
            TestCase(
                description: "fails when one element does not match",
                pattern: "^[A-Z][a-zA-Z0-9]*$",
                input: "ModuleA, invalid-name, ModuleC",
                expected: false
            ),
            TestCase(
                description: "validates empty array",
                pattern: "^[A-Z][a-zA-Z0-9]*$",
                input: "",
                expected: true
            ),
            TestCase(
                description: "validates single element",
                pattern: "^[A-Z][a-zA-Z0-9]*$",
                input: "ValidModule",
                expected: true
            ),
            TestCase(
                description: "handles whitespace correctly",
                pattern: "^[A-Z][a-zA-Z0-9]*$",
                input: "  ModuleA  ,  ModuleB  ",
                expected: true
            ),
            TestCase(
                description: "validates lowercase package names",
                pattern: "^[a-z][a-z0-9-]*$",
                input: "package-a, package-b, my-package",
                expected: true
            ),
            TestCase(
                description: "fails with uppercase in lowercase pattern",
                pattern: "^[a-z][a-z0-9-]*$",
                input: "package-a, Package-B",
                expected: false
            ),
            TestCase(
                description: "validates numbers in pattern",
                pattern: "^[a-z0-9]+$",
                input: "abc123, def456",
                expected: true
            ),
            TestCase(
                description: "fails with special characters not in pattern",
                pattern: "^[a-z0-9]+$",
                input: "abc123, def_456",
                expected: false
            ),
            TestCase(
                description: "handles comma without spaces",
                pattern: "^[A-Z][a-zA-Z0-9]*$",
                input: "ModuleA,ModuleB,ModuleC",
                expected: true
            ),
            TestCase(
                description: "returns false for invalid regex pattern",
                pattern: "[invalid(regex",
                input: "anything",
                expected: false
            ),
        ]
    }
}
