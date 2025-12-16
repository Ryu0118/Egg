@testable import EggKit
import Testing

struct ConfigValidatorArrayFormatTests {
    let validator = ConfigValidator()

    @Test(arguments: TestCase.allCases)
    func validate(_ testCase: TestCase) async throws {
        do {
            try await validator.validate(testCase.config)

            if case let .failure(expectedMessages) = testCase.expected {
                #expect(Bool(false), "Expected errors \(expectedMessages)")
            }
        } catch {
            switch testCase.expected {
            case .success:
                throw error
            case let .failure(expectedErrors):
                guard let combinedError = error as? CombinedError else {
                    throw error
                }

                let actualErrors = combinedError.errors
                    .compactMap { $0 as? ConfigValidator.Error }
                #expect(actualErrors == expectedErrors)
            }
        }
    }

    struct TestCase: CustomTestStringConvertible {
        let description: String
        let config: Config
        let expected: Result

        var testDescription: String { description }

        enum Result {
            case success
            case failure([ConfigValidator.Error])
        }

        static let allCases: [TestCase] = [
            TestCase(
                description: "passes with valid array format expression",
                config: makeConfig(
                    macros: [
                        Config.Macro(
                            name: "___PLATFORMS___",
                            description: "Platforms",
                            type: .array,
                            default: #"["iOS", "macOS"]"#,
                            format: #"$elements.map(x => `.${x}`).join(", ")"#
                        ),
                    ]
                ),
                expected: .success
            ),
            TestCase(
                description: "passes with array without format (uses default)",
                config: makeConfig(
                    macros: [
                        Config.Macro(
                            name: "___TAGS___",
                            description: "Tags",
                            type: .array,
                            default: #"["swift"]"#
                        ),
                    ]
                ),
                expected: .success
            ),
            TestCase(
                description: "passes with array without choices (free input)",
                config: makeConfig(
                    macros: [
                        Config.Macro(
                            name: "___DEPENDENCIES___",
                            description: "Dependencies",
                            type: .array,
                            default: "[]"
                        ),
                    ]
                ),
                expected: .success
            ),
            TestCase(
                description: "fails with format on non-array type",
                config: makeConfig(
                    macros: [
                        Config.Macro(
                            name: "___NAME___",
                            description: "Name",
                            type: .string,
                            format: #"$elements.join(", ")"#
                        ),
                    ]
                ),
                expected: .failure([
                    .formatOnlyValidForArrayType(context: "macros[0]", name: "___NAME___"),
                ])
            ),
            TestCase(
                description: "fails with format on choice type",
                config: makeConfig(
                    macros: [
                        Config.Macro(
                            name: "___TYPE___",
                            description: "Type",
                            type: .choice,
                            default: "a",
                            choices: ["a", "b"],
                            format: #"$elements.join(", ")"#
                        ),
                    ]
                ),
                expected: .failure([
                    .formatOnlyValidForArrayType(context: "macros[0]", name: "___TYPE___"),
                ])
            ),
            TestCase(
                description: "fails with format on boolean type",
                config: makeConfig(
                    macros: [
                        Config.Macro(
                            name: "___ENABLED___",
                            description: "Enabled",
                            type: .boolean,
                            default: "true",
                            format: #"$elements.join(", ")"#
                        ),
                    ]
                ),
                expected: .failure([
                    .formatOnlyValidForArrayType(context: "macros[0]", name: "___ENABLED___"),
                ])
            ),
            TestCase(
                description: "fails with invalid format syntax",
                config: makeConfig(
                    macros: [
                        Config.Macro(
                            name: "___PLATFORMS___",
                            description: "Platforms",
                            type: .array,
                            default: #"["iOS"]"#,
                            format: "$elements.map(x =>"
                        ),
                    ]
                ),
                expected: .failure([
                    .invalidFormatExpression(context: "macros[0]", name: "___PLATFORMS___", format: "$elements.map(x =>"),
                ])
            ),
            TestCase(
                description: "fails with format returning non-string",
                config: makeConfig(
                    macros: [
                        Config.Macro(
                            name: "___PLATFORMS___",
                            description: "Platforms",
                            type: .array,
                            default: #"["iOS"]"#,
                            format: "$elements.length"
                        ),
                    ]
                ),
                expected: .failure([
                    .invalidFormatExpression(context: "macros[0]", name: "___PLATFORMS___", format: "$elements.length"),
                ])
            ),
            TestCase(
                description: "fails with format returning undefined",
                config: makeConfig(
                    macros: [
                        Config.Macro(
                            name: "___PLATFORMS___",
                            description: "Platforms",
                            type: .array,
                            default: #"["iOS"]"#,
                            format: "$elements.find(x => x === 'notfound')"
                        ),
                    ]
                ),
                expected: .failure([
                    .invalidFormatExpression(context: "macros[0]", name: "___PLATFORMS___", format: "$elements.find(x => x === 'notfound')"),
                ])
            ),
            TestCase(
                description: "aggregates format and other validation errors",
                config: makeConfig(
                    macros: [
                        Config.Macro(
                            name: "___NAME___",
                            description: "Name",
                            type: .string,
                            format: #"$elements.join(", ")"#
                        ),
                        Config.Macro(
                            name: "___PLATFORMS___",
                            description: "Platforms",
                            type: .array,
                            default: #"["iOS"]"#,
                            format: "$elements.map(x =>"
                        ),
                    ]
                ),
                expected: .failure([
                    .formatOnlyValidForArrayType(context: "macros[0]", name: "___NAME___"),
                    .invalidFormatExpression(context: "macros[1]", name: "___PLATFORMS___", format: "$elements.map(x =>"),
                ])
            ),

            TestCase(
                description: "fails with choices on string type",
                config: makeConfig(
                    macros: [
                        Config.Macro(
                            name: "___NAME___",
                            description: "Name",
                            type: .string,
                            choices: ["a", "b", "c"]
                        ),
                    ]
                ),
                expected: .failure([
                    .choicesOnlyValidForChoiceTypes(context: "macros[0]", name: "___NAME___"),
                ])
            ),
            TestCase(
                description: "fails with choices on boolean type",
                config: makeConfig(
                    macros: [
                        Config.Macro(
                            name: "___ENABLED___",
                            description: "Enabled",
                            type: .boolean,
                            default: "true",
                            choices: ["true", "false"]
                        ),
                    ]
                ),
                expected: .failure([
                    .choicesOnlyValidForChoiceTypes(context: "macros[0]", name: "___ENABLED___"),
                ])
            ),
            TestCase(
                description: "fails with choices on path type",
                config: makeConfig(
                    macros: [
                        Config.Macro(
                            name: "___PATH___",
                            description: "Path",
                            type: .path,
                            choices: ["/a", "/b"]
                        ),
                    ]
                ),
                expected: .failure([
                    .choicesOnlyValidForChoiceTypes(context: "macros[0]", name: "___PATH___"),
                ])
            ),
            TestCase(
                description: "passes with choices on choice type",
                config: makeConfig(
                    macros: [
                        Config.Macro(
                            name: "___TYPE___",
                            description: "Type",
                            type: .choice,
                            default: "a",
                            choices: ["a", "b"]
                        ),
                    ]
                ),
                expected: .success
            ),
            TestCase(
                description: "passes with choices on choices type",
                config: makeConfig(
                    macros: [
                        Config.Macro(
                            name: "___TYPES___",
                            description: "Types",
                            type: .choices,
                            default: #"["a"]"#,
                            choices: ["a", "b", "c"]
                        ),
                    ]
                ),
                expected: .success
            ),
            TestCase(
                description: "fails with choices on array type",
                config: makeConfig(
                    macros: [
                        Config.Macro(
                            name: "___PLATFORMS___",
                            description: "Platforms",
                            type: .array,
                            default: #"["iOS"]"#,
                            choices: ["iOS", "macOS", "watchOS"]
                        ),
                    ]
                ),
                expected: .failure([
                    .choicesOnlyValidForChoiceTypes(context: "macros[0]", name: "___PLATFORMS___"),
                ])
            ),

            TestCase(
                description: "fails with validate on boolean type",
                config: makeConfig(
                    macros: [
                        Config.Macro(
                            name: "___ENABLED___",
                            description: "Enabled",
                            type: .boolean,
                            default: "true",
                            validate: "^(true|false)$"
                        ),
                    ]
                ),
                expected: .failure([
                    .validateOnlyValidForStringAndArrayTypes(context: "macros[0]", name: "___ENABLED___"),
                ])
            ),
            TestCase(
                description: "fails with validate on choice type",
                config: makeConfig(
                    macros: [
                        Config.Macro(
                            name: "___TYPE___",
                            description: "Type",
                            type: .choice,
                            default: "a",
                            validate: "^[a-z]$",
                            choices: ["a", "b"]
                        ),
                    ]
                ),
                expected: .failure([
                    .validateOnlyValidForStringAndArrayTypes(context: "macros[0]", name: "___TYPE___"),
                ])
            ),
            TestCase(
                description: "passes with validate on array type",
                config: makeConfig(
                    macros: [
                        Config.Macro(
                            name: "___PLATFORMS___",
                            description: "Platforms",
                            type: .array,
                            default: #"["iOS"]"#,
                            validate: ".*"
                        ),
                    ]
                ),
                expected: .success
            ),
            TestCase(
                description: "fails with validate on path type",
                config: makeConfig(
                    macros: [
                        Config.Macro(
                            name: "___PATH___",
                            description: "Path",
                            type: .path,
                            validate: "^/.*$"
                        ),
                    ]
                ),
                expected: .failure([
                    .validateOnlyValidForStringAndArrayTypes(context: "macros[0]", name: "___PATH___"),
                ])
            ),
            TestCase(
                description: "passes with validate on string type",
                config: makeConfig(
                    macros: [
                        Config.Macro(
                            name: "___NAME___",
                            description: "Name",
                            type: .string,
                            default: "test",
                            validate: "^[a-z]+$"
                        ),
                    ]
                ),
                expected: .success
            ),
            TestCase(
                description: "passes with validate on array type without default",
                config: makeConfig(
                    macros: [
                        Config.Macro(
                            name: "___MODULES___",
                            description: "Modules",
                            type: .array,
                            validate: "^[A-Z][a-zA-Z0-9]*$"
                        ),
                    ]
                ),
                expected: .success
            ),
            TestCase(
                description: "passes with validate on array type with format",
                config: makeConfig(
                    macros: [
                        Config.Macro(
                            name: "___PACKAGES___",
                            description: "Packages",
                            type: .array,
                            validate: "^[a-z][a-z0-9-]*$",
                            format: #"$elements.map(x => `.package(name: "${x}")`).join(", ")"#
                        ),
                    ]
                ),
                expected: .success
            ),

            TestCase(
                description: "aggregates multiple field compatibility errors",
                config: makeConfig(
                    macros: [
                        Config.Macro(
                            name: "___BAD___",
                            description: "Bad",
                            type: .boolean,
                            default: "true",
                            validate: ".*",
                            choices: ["true", "false"],
                            format: #"$elements.join(", ")"#
                        ),
                    ]
                ),
                expected: .failure([
                    .formatOnlyValidForArrayType(context: "macros[0]", name: "___BAD___"),
                    .choicesOnlyValidForChoiceTypes(context: "macros[0]", name: "___BAD___"),
                    .validateOnlyValidForStringAndArrayTypes(context: "macros[0]", name: "___BAD___"),
                ])
            ),
        ]
    }

    private static func makeConfig(
        name: String = "TestTemplate",
        description: String = "Test",
        macros: [Config.Macro] = []
    ) -> Config {
        Config(
            name: name,
            description: description,
            macros: macros,
            preHatch: nil,
            hatch: Config.HatchConfig(output: "output"),
            postHatch: nil
        )
    }
}
