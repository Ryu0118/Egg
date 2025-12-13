@testable import EggKit
import Testing

struct ArrayFormatEvaluatorTests {
    private let evaluator = ArrayFormatEvaluator()

    @Test(arguments: EvaluateTestCase.allCases)
    func evaluate(_ testCase: EvaluateTestCase) throws {
        switch testCase.expected {
        case let .success(expectedResult):
            let result = try evaluator.evaluate(format: testCase.format, values: testCase.values)
            #expect(result == expectedResult)
        case let .failure(expectedError):
            #expect(throws: expectedError) {
                _ = try evaluator.evaluate(format: testCase.format, values: testCase.values)
            }
        }
    }

    struct EvaluateTestCase: CustomTestStringConvertible {
        let description: String
        let format: String
        let values: [String]
        let expected: Result

        var testDescription: String { description }

        enum Result {
            case success(String)
            case failure(ArrayFormatError)
        }

        static let allCases: [EvaluateTestCase] = [
            // Basic formats
            EvaluateTestCase(
                description: "joins array with default separator",
                format: #"$elements.join(", ")"#,
                values: ["iOS", "macOS", "watchOS"],
                expected: .success("iOS, macOS, watchOS")
            ),
            EvaluateTestCase(
                description: "maps and joins with dot prefix",
                format: #"$elements.map(x => `.${x}`).join(", ")"#,
                values: ["iOS", "macOS"],
                expected: .success(".iOS, .macOS")
            ),
            EvaluateTestCase(
                description: "creates JSON array format",
                format: #""[" + $elements.map(x => `"${x}"`).join(", ") + "]""#,
                values: ["swift", "template"],
                expected: .success(#"["swift", "template"]"#)
            ),
            EvaluateTestCase(
                description: "joins with newline for import statements",
                format: #"$elements.map(x => `import ${x}`).join("\n")"#,
                values: ["Foundation", "UIKit"],
                expected: .success("import Foundation\nimport UIKit")
            ),
            EvaluateTestCase(
                description: "creates SPM package declarations",
                format: #"$elements.map(x => `.package(name: "${x}")`).join(",\n")"#,
                values: ["Alamofire", "SwiftyJSON"],
                expected: .success(".package(name: \"Alamofire\"),\n.package(name: \"SwiftyJSON\")")
            ),
            EvaluateTestCase(
                description: "transforms with regex to kebab-case",
                format: #"$elements.map(x => x.replace(/([A-Z])/g, "-$1").toLowerCase().slice(1)).join(", ")"#,
                values: ["MyModule", "NetworkClient"],
                expected: .success("my-module, network-client")
            ),

            // Edge cases
            EvaluateTestCase(
                description: "returns empty string for empty array",
                format: #"$elements.join(", ")"#,
                values: [],
                expected: .success("")
            ),
            EvaluateTestCase(
                description: "formats single element without separator",
                format: #"$elements.map(x => `.${x}`).join(", ")"#,
                values: ["iOS"],
                expected: .success(".iOS")
            ),
            EvaluateTestCase(
                description: "handles elements with special characters",
                format: #"$elements.join(", ")"#,
                values: ["Hello World", "Foo\"Bar"],
                expected: .success("Hello World, Foo\"Bar")
            ),

            // Error cases
            EvaluateTestCase(
                description: "fails when format returns number",
                format: "$elements.length",
                values: ["iOS", "macOS"],
                expected: .failure(.nonStringResult(format: "$elements.length", actualType: "number"))
            ),
            EvaluateTestCase(
                description: "fails when format returns undefined",
                format: "$elements.find(x => x === 'notfound')",
                values: ["iOS"],
                expected: .failure(.evaluationFailed(format: "$elements.find(x => x === 'notfound')"))
            ),
        ]
    }
}
