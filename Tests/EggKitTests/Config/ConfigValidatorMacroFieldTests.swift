@testable import EggKit
import Testing

struct ConfigValidatorMacroFieldTests {
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

        static let allCases: [TestCase] = [
            // MARK: - Array type

            TestCase(
                description: "passes with array type",
                config: makeConfig(
                    macros: [
                        Config.Macro(
                            name: "___TAGS___",
                            description: "Tags",
                            type: .array,
                            default: #"["swift"]"#,
                        ),
                    ],
                ),
                expected: .success,
            ),
            TestCase(
                description: "passes with array without choices (free input)",
                config: makeConfig(
                    macros: [
                        Config.Macro(
                            name: "___DEPENDENCIES___",
                            description: "Dependencies",
                            type: .array,
                            default: "[]",
                        ),
                    ],
                ),
                expected: .success,
            ),

            // MARK: - choices field compatibility

            TestCase(
                description: "fails with choices on string type",
                config: makeConfig(
                    macros: [
                        Config.Macro(
                            name: "___NAME___",
                            description: "Name",
                            type: .string,
                            choices: ["a", "b", "c"],
                        ),
                    ],
                ),
                expected: .failure([
                    .choicesOnlyValidForChoiceTypes(context: "macros[0]", name: "___NAME___"),
                ]),
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
                            choices: ["true", "false"],
                        ),
                    ],
                ),
                expected: .failure([
                    .choicesOnlyValidForChoiceTypes(context: "macros[0]", name: "___ENABLED___"),
                ]),
            ),
            TestCase(
                description: "fails with choices on path type",
                config: makeConfig(
                    macros: [
                        Config.Macro(
                            name: "___PATH___",
                            description: "Path",
                            type: .path,
                            choices: ["/a", "/b"],
                        ),
                    ],
                ),
                expected: .failure([
                    .choicesOnlyValidForChoiceTypes(context: "macros[0]", name: "___PATH___"),
                ]),
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
                            choices: ["a", "b"],
                        ),
                    ],
                ),
                expected: .success,
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
                            choices: ["a", "b", "c"],
                        ),
                    ],
                ),
                expected: .success,
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
                            choices: ["iOS", "macOS", "watchOS"],
                        ),
                    ],
                ),
                expected: .failure([
                    .choicesOnlyValidForChoiceTypes(context: "macros[0]", name: "___PLATFORMS___"),
                ]),
            ),

            // MARK: - validate field compatibility

            TestCase(
                description: "fails with validate on boolean type",
                config: makeConfig(
                    macros: [
                        Config.Macro(
                            name: "___ENABLED___",
                            description: "Enabled",
                            type: .boolean,
                            default: "true",
                            validate: "^(true|false)$",
                        ),
                    ],
                ),
                expected: .failure([
                    .validateOnlyValidForStringAndArrayTypes(context: "macros[0]", name: "___ENABLED___"),
                ]),
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
                            choices: ["a", "b"],
                        ),
                    ],
                ),
                expected: .failure([
                    .validateOnlyValidForStringAndArrayTypes(context: "macros[0]", name: "___TYPE___"),
                ]),
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
                            validate: ".*",
                        ),
                    ],
                ),
                expected: .success,
            ),
            TestCase(
                description: "fails with validate on path type",
                config: makeConfig(
                    macros: [
                        Config.Macro(
                            name: "___PATH___",
                            description: "Path",
                            type: .path,
                            validate: "^/.*$",
                        ),
                    ],
                ),
                expected: .failure([
                    .validateOnlyValidForStringAndArrayTypes(context: "macros[0]", name: "___PATH___"),
                ]),
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
                            validate: "^[a-z]+$",
                        ),
                    ],
                ),
                expected: .success,
            ),
            TestCase(
                description: "passes with validate on array type without default",
                config: makeConfig(
                    macros: [
                        Config.Macro(
                            name: "___MODULES___",
                            description: "Modules",
                            type: .array,
                            validate: "^[A-Z][a-zA-Z0-9]*$",
                        ),
                    ],
                ),
                expected: .success,
            ),

            // MARK: - Aggregation

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
                        ),
                    ],
                ),
                expected: .failure([
                    .choicesOnlyValidForChoiceTypes(context: "macros[0]", name: "___BAD___"),
                    .validateOnlyValidForStringAndArrayTypes(context: "macros[0]", name: "___BAD___"),
                ]),
            ),
        ]

        enum Result {
            case success
            case failure([ConfigValidator.Error])
        }

        var testDescription: String {
            description
        }
    }

    private static func makeConfig(
        name: String = "TestTemplate",
        description: String = "Test",
        macros: [Config.Macro] = [],
    ) -> Config {
        Config(
            name: name,
            description: description,
            macros: macros,
            preHatch: nil,
            hatch: Config.HatchConfig(output: "output"),
            postHatch: nil,
        )
    }
}
