@testable import EggKit
import Foundation
import Testing

struct VariableResolverArrayFormatTests {
    @Test(arguments: TestCase.allCases)
    func resolve(_ testCase: TestCase) async throws {
        let resolver = VariableResolver(
            macros: testCase.macros,
            outputs: StepOutputsStorage(),
            builtInMacroContext: TestCase.defaultBuiltInMacroContext
        )
        let result = try await resolver.resolve(testCase.input)
        #expect(result == testCase.expected)
    }

    struct TestCase: CustomTestStringConvertible {
        let description: String
        let input: String
        let macros: [ResolvedMacro]
        let expected: String

        var testDescription: String { description }

        static let defaultBuiltInMacroContext = BuiltInMacroContext(
            outputDirectory: nil,
            workingDirectory: URL(filePath: "/tmp/work"),
            homeDirectory: URL(filePath: "/tmp/home"),
            currentDate: Date(timeIntervalSince1970: 0),
            environment: [:]
        )

        static let allCases: [TestCase] = [
            TestCase(
                description: "resolves array with dot prefix format",
                input: "platforms: [___PLATFORMS___]",
                macros: [
                    ResolvedMacro(
                        name: "___PLATFORMS___",
                        description: "Platforms",
                        value: .array(["iOS", "macOS"], format: #"$elements.map(x => `.${x}`).join(", ")"#)
                    ),
                ],
                expected: "platforms: [.iOS, .macOS]"
            ),
            TestCase(
                description: "resolves array with default join format (nil)",
                input: "tags: ___TAGS___",
                macros: [
                    ResolvedMacro(
                        name: "___TAGS___",
                        description: "Tags",
                        value: .array(["swift", "library"], format: nil)
                    ),
                ],
                expected: "tags: swift, library"
            ),
            TestCase(
                description: "resolves array with explicit join format",
                input: "tags: ___TAGS___",
                macros: [
                    ResolvedMacro(
                        name: "___TAGS___",
                        description: "Tags",
                        value: .array(["swift", "library"], format: #"$elements.join(", ")"#)
                    ),
                ],
                expected: "tags: swift, library"
            ),
            TestCase(
                description: "resolves array with JSON format",
                input: "keywords: ___KEYWORDS___",
                macros: [
                    ResolvedMacro(
                        name: "___KEYWORDS___",
                        description: "Keywords",
                        value: .array(["swift", "template"], format: #""[" + $elements.map(x => `"${x}"`).join(", ") + "]""#)
                    ),
                ],
                expected: #"keywords: ["swift", "template"]"#
            ),
            TestCase(
                description: "resolves empty array",
                input: "deps: ___DEPENDENCIES___",
                macros: [
                    ResolvedMacro(
                        name: "___DEPENDENCIES___",
                        description: "Dependencies",
                        value: .array([], format: #"$elements.join(", ")"#)
                    ),
                ],
                expected: "deps: "
            ),
            TestCase(
                description: "resolves array with newline separator",
                input: "list:\n___ITEMS___",
                macros: [
                    ResolvedMacro(
                        name: "___ITEMS___",
                        description: "Items",
                        value: .array(["item1", "item2", "item3"], format: #"$elements.map(x => `- ${x}`).join("\n")"#)
                    ),
                ],
                expected: "list:\n- item1\n- item2\n- item3"
            ),
            TestCase(
                description: "resolves array with single element",
                input: "platform: ___PLATFORM___",
                macros: [
                    ResolvedMacro(
                        name: "___PLATFORM___",
                        description: "Platform",
                        value: .array(["iOS"], format: nil)
                    ),
                ],
                expected: "platform: iOS"
            ),
            TestCase(
                description: "resolves multiple array macros",
                input: "platforms: ___PLATFORMS___, tags: ___TAGS___",
                macros: [
                    ResolvedMacro(
                        name: "___PLATFORMS___",
                        description: "Platforms",
                        value: .array(["iOS", "macOS"], format: nil)
                    ),
                    ResolvedMacro(
                        name: "___TAGS___",
                        description: "Tags",
                        value: .array(["swift", "library"], format: nil)
                    ),
                ],
                expected: "platforms: iOS, macOS, tags: swift, library"
            ),
        ]
    }
}
