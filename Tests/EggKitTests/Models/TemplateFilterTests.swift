@testable import EggKit
import Testing

struct TemplateFilterTests {
    @Test(arguments: TestCase.allCases)
    func `should include`(_ testCase: TestCase) {
        let result = testCase.filter.shouldInclude(testCase.templateName)
        #expect(result == testCase.expected)
    }

    struct TestCase: CustomTestStringConvertible {
        let description: String
        let filter: TemplateFilter
        let templateName: String
        let expected: Bool

        var testDescription: String {
            description
        }

        static let allCases: [TestCase] = [
            // .none filter - includes everything
            TestCase(
                description: "none filter includes any template",
                filter: .none,
                templateName: "swift-module",
                expected: true,
            ),
            TestCase(
                description: "none filter includes another template",
                filter: .none,
                templateName: "any-template",
                expected: true,
            ),

            // .include filter - only includes specified templates
            TestCase(
                description: "include filter includes specified template",
                filter: .include(["swift-module", "swift-package"]),
                templateName: "swift-module",
                expected: true,
            ),
            TestCase(
                description: "include filter includes another specified template",
                filter: .include(["swift-module", "swift-package"]),
                templateName: "swift-package",
                expected: true,
            ),
            TestCase(
                description: "include filter excludes non-specified template",
                filter: .include(["swift-module", "swift-package"]),
                templateName: "swiftui-view",
                expected: false,
            ),
            TestCase(
                description: "include filter with single template includes it",
                filter: .include(["swift-module"]),
                templateName: "swift-module",
                expected: true,
            ),
            TestCase(
                description: "include filter with empty array excludes all",
                filter: .include([]),
                templateName: "swift-module",
                expected: false,
            ),

            // .exclude filter - excludes specified templates
            TestCase(
                description: "exclude filter excludes specified template",
                filter: .exclude(["swift-module", "swift-package"]),
                templateName: "swift-module",
                expected: false,
            ),
            TestCase(
                description: "exclude filter excludes another specified template",
                filter: .exclude(["swift-module", "swift-package"]),
                templateName: "swift-package",
                expected: false,
            ),
            TestCase(
                description: "exclude filter includes non-specified template",
                filter: .exclude(["swift-module", "swift-package"]),
                templateName: "swiftui-view",
                expected: true,
            ),
            TestCase(
                description: "exclude filter with single template excludes it",
                filter: .exclude(["swift-module"]),
                templateName: "swift-module",
                expected: false,
            ),
            TestCase(
                description: "exclude filter with empty array includes all",
                filter: .exclude([]),
                templateName: "swift-module",
                expected: true,
            ),
        ]
    }
}
