@testable import EggKit
import Foundation
import Interaction
import Testing

struct ConfigValidatorTests {
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
            // Success cases
            TestCase(
                description: "passes with a fully valid config",
                config: makeValidConfig(),
                expected: .success,
            ),
            TestCase(
                description: "passes with boolean macro and condition",
                config: Config(
                    name: "TestTemplate",
                    description: "Test",
                    macros: [
                        Config.Macro(name: "___CREATE_TESTS___", description: "Create tests", type: .boolean, default: "true"),
                    ],
                    preHatch: [
                        Config.LifecycleStep(if: "___CREATE_TESTS___", run: "echo test"),
                    ],
                    hatch: Config.HatchConfig(output: "output"),
                    postHatch: nil,
                ),
                expected: .success,
            ),
            TestCase(
                description: "passes with choice macro and comparison condition",
                config: Config(
                    name: "TestTemplate",
                    description: "Test",
                    macros: [
                        Config.Macro(name: "___MODULE_TYPE___", description: "Type", type: .choice, default: "library", choices: ["library", "executable"]),
                    ],
                    preHatch: [
                        Config.LifecycleStep(if: "___MODULE_TYPE___ === \"library\"", run: "echo library"),
                    ],
                    hatch: Config.HatchConfig(output: "output"),
                    postHatch: nil,
                ),
                expected: .success,
            ),
            TestCase(
                description: "passes with array macro and indexOf condition",
                config: Config(
                    name: "TestTemplate",
                    description: "Test",
                    macros: [
                        Config.Macro(name: "___PLATFORMS___", description: "Platforms", type: .array, default: "[\"iOS\", \"macOS\"]"),
                    ],
                    preHatch: [
                        Config.LifecycleStep(if: "___PLATFORMS___.indexOf(\"iOS\") !== -1", run: "echo iOS"),
                    ],
                    hatch: Config.HatchConfig(output: "output"),
                    postHatch: nil,
                ),
                expected: .success,
            ),
            TestCase(
                description: "passes with path macro",
                config: Config(
                    name: "TestTemplate",
                    description: "Test",
                    macros: [
                        Config.Macro(name: "___PACKAGE_PATH___", description: "Path", type: .path, default: "/path/to/project"),
                    ],
                    preHatch: [
                        Config.LifecycleStep(run: "cd ___PACKAGE_PATH___"),
                    ],
                    hatch: Config.HatchConfig(output: "output"),
                    postHatch: nil,
                ),
                expected: .success,
            ),
            TestCase(
                description: "passes with string macro and regex validation",
                config: Config(
                    name: "TestTemplate",
                    description: "Test",
                    macros: [
                        Config.Macro(name: "___MODULE_NAME___", description: "Name", type: .string, default: "MyModule", validate: "^[A-Z][a-zA-Z0-9]*$"),
                    ],
                    preHatch: nil,
                    hatch: Config.HatchConfig(output: "output"),
                    postHatch: nil,
                ),
                expected: .success,
            ),
            TestCase(
                description: "passes with conditional exclude",
                config: Config(
                    name: "TestTemplate",
                    description: "Test",
                    macros: [
                        Config.Macro(name: "___CREATE_TESTS___", description: "Create tests", type: .boolean, default: "false"),
                    ],
                    preHatch: nil,
                    hatch: Config.HatchConfig(
                        output: "output",
                        exclude: [
                            .path("*.md"),
                            .conditional(Config.ConditionalExclude(if: "!___CREATE_TESTS___", paths: ["Tests/**"])),
                        ],
                    ),
                    postHatch: nil,
                ),
                expected: .success,
            ),
            TestCase(
                description: "passes with multiple exclude rules",
                config: Config(
                    name: "TestTemplate",
                    description: "Test",
                    macros: [
                        Config.Macro(name: "___MODULE_TYPE___", description: "Type", type: .choice, default: "library", choices: ["library", "executable"]),
                    ],
                    preHatch: nil,
                    hatch: Config.HatchConfig(
                        output: "output",
                        exclude: [
                            .path("*.md"),
                            .path(".DS_Store"),
                            .conditional(Config.ConditionalExclude(if: "___MODULE_TYPE___ !== \"executable\"", paths: ["main.swift"])),
                        ],
                    ),
                    postHatch: nil,
                ),
                expected: .success,
            ),
            TestCase(
                description: "passes with post_hatch conditions",
                config: Config(
                    name: "TestTemplate",
                    description: "Test",
                    macros: [
                        Config.Macro(name: "___CREATE_TESTS___", description: "Create tests", type: .boolean, default: "true"),
                        Config.Macro(name: "___MODULE_TYPE___", description: "Type", type: .choice, default: "executable", choices: ["library", "executable"]),
                    ],
                    preHatch: nil,
                    hatch: Config.HatchConfig(output: "output"),
                    postHatch: [
                        Config.LifecycleStep(if: "___CREATE_TESTS___", run: "swift test"),
                        Config.LifecycleStep(if: "___MODULE_TYPE___ === \"executable\"", run: "swift build"),
                    ],
                ),
                expected: .success,
            ),
            TestCase(
                description: "passes with step outputs in condition",
                config: Config(
                    name: "TestTemplate",
                    description: "Test",
                    macros: [
                        Config.Macro(name: "___NAME___", description: "Name", default: "test"),
                    ],
                    preHatch: [
                        Config.LifecycleStep(id: "setup", run: "echo ready=true"),
                    ],
                    hatch: Config.HatchConfig(output: "output"),
                    postHatch: [
                        Config.LifecycleStep(if: "${{ pre_hatch.setup.outputs.ready }} === \"true\"", run: "echo done"),
                    ],
                ),
                expected: .success,
            ),
            TestCase(
                description: "passes with logical operators in condition",
                config: Config(
                    name: "TestTemplate",
                    description: "Test",
                    macros: [
                        Config.Macro(name: "___A___", description: "A", type: .boolean, default: "true"),
                        Config.Macro(name: "___B___", description: "B", type: .boolean, default: "false"),
                    ],
                    preHatch: [
                        Config.LifecycleStep(if: "___A___ && ___B___", run: "echo both"),
                        Config.LifecycleStep(if: "___A___ || ___B___", run: "echo either"),
                    ],
                    hatch: Config.HatchConfig(output: "output"),
                    postHatch: nil,
                ),
                expected: .success,
            ),
            TestCase(
                description: "passes with empty macros array",
                config: Config(
                    name: "TestTemplate",
                    description: "Test",
                    macros: [],
                    preHatch: nil,
                    hatch: Config.HatchConfig(output: "output"),
                    postHatch: nil,
                ),
                expected: .success,
            ),
            TestCase(
                description: "passes with no pre_hatch or post_hatch",
                config: Config(
                    name: "TestTemplate",
                    description: "Test",
                    macros: nil,
                    preHatch: nil,
                    hatch: Config.HatchConfig(output: "output"),
                    postHatch: nil,
                ),
                expected: .success,
            ),
            TestCase(
                description: "passes with built-in macros referenced in run command",
                config: Config(
                    name: "TestTemplate",
                    description: "Test",
                    macros: nil,
                    preHatch: [
                        Config.LifecycleStep(run: "echo ___DATE___ ___YEAR___ ___SYSTEM_USER___ ___UUID___"),
                    ],
                    hatch: Config.HatchConfig(output: "output"),
                    postHatch: nil,
                ),
                expected: .success,
            ),
            TestCase(
                description: "fails when template name violates validation rules",
                config: makeValidConfig(name: "/invalid"),
                expected: .failure([
                    .validationRuleError(ValidationError("Invalid directory name. Cannot contain '/' or start with whitespace.")),
                ]),
            ),
            TestCase(
                description: "detects empty macro name",
                config: makeValidConfig(macros: [
                    Config.Macro(name: "", description: "desc"),
                ]),
                expected: .failure([
                    .macroNameEmpty(context: "macros[0]"),
                ]),
            ),
            TestCase(
                description: "detects empty macro description",
                config: makeValidConfig(macros: [
                    Config.Macro(name: "___NAME___", description: ""),
                ]),
                expected: .failure([
                    .macroDescriptionEmpty(context: "macros[0]"),
                ]),
            ),
            TestCase(
                description: "detects invalid macro name format",
                config: makeValidConfig(macros: [
                    Config.Macro(name: "___lower___", description: "desc"),
                ]),
                expected: .failure([
                    .invalidMacroNameFormat(context: "macros[0]", name: "___lower___"),
                ]),
            ),
            TestCase(
                description: "detects duplicate macro names",
                config: makeValidConfig(macros: [
                    Config.Macro(name: "___DUP___", description: "first"),
                    Config.Macro(name: "___DUP___", description: "second"),
                ]),
                expected: .failure([
                    .duplicateMacroName(context: "macros[1]", name: "___DUP___"),
                ]),
            ),
            TestCase(
                description: "detects reserved macro name ___DATE___",
                config: makeValidConfig(macros: [
                    Config.Macro(name: "___DATE___", description: "desc"),
                ]),
                expected: .failure([
                    .reservedMacroName(context: "macros[0]", name: "___DATE___"),
                ]),
            ),
            TestCase(
                description: "detects reserved macro name ___YEAR___",
                config: makeValidConfig(macros: [
                    Config.Macro(name: "___YEAR___", description: "desc"),
                ]),
                expected: .failure([
                    .reservedMacroName(context: "macros[0]", name: "___YEAR___"),
                ]),
            ),
            TestCase(
                description: "detects reserved macro name ___SYSTEM_USER___",
                config: makeValidConfig(macros: [
                    Config.Macro(name: "___SYSTEM_USER___", description: "desc"),
                ]),
                expected: .failure([
                    .reservedMacroName(context: "macros[0]", name: "___SYSTEM_USER___"),
                ]),
            ),
            TestCase(
                description: "detects reserved macro name ___UUID___",
                config: makeValidConfig(macros: [
                    Config.Macro(name: "___UUID___", description: "desc"),
                ]),
                expected: .failure([
                    .reservedMacroName(context: "macros[0]", name: "___UUID___"),
                ]),
            ),
            TestCase(
                description: "detects missing choices for choice macro",
                config: makeValidConfig(macros: [
                    Config.Macro(name: "___CHOICE___", description: "desc", type: .choice, choices: nil),
                ]),
                expected: .failure([
                    .choiceTypeMissingChoices(context: "macros[0]", name: "___CHOICE___"),
                ]),
            ),
            TestCase(
                description: "detects empty choices for choice macro",
                config: makeValidConfig(macros: [
                    Config.Macro(name: "___CHOICE___", description: "desc", type: .choice, choices: []),
                ]),
                expected: .failure([
                    .choiceTypeEmptyChoices(context: "macros[0]", name: "___CHOICE___"),
                ]),
            ),
            TestCase(
                description: "detects default value not in choices for choice macro",
                config: makeValidConfig(macros: [
                    Config.Macro(name: "___CHOICE___", description: "desc", type: .choice, default: "c", choices: ["a", "b"]),
                ]),
                expected: .failure([
                    .choiceDefaultValueNotInChoices(context: "macros[0]", name: "___CHOICE___", defaultValue: "c", choices: ["a", "b"]),
                ]),
            ),
            TestCase(
                description: "detects choices specified for array macro",
                config: makeValidConfig(macros: [
                    Config.Macro(name: "___ARRAY___", description: "desc", type: .array, default: "[\"a\"]", choices: ["a", "b"]),
                ]),
                expected: .failure([
                    .choicesOnlyValidForChoiceTypes(context: "macros[0]", name: "___ARRAY___"),
                ]),
            ),
            TestCase(
                description: "detects choices default values outside options for choices macro",
                config: makeValidConfig(macros: [
                    Config.Macro(name: "___CHOICES___", description: "desc", type: .choices, default: #"["c"]"#, choices: ["a", "b"]),
                ]),
                expected: .failure([
                    .arrayDefaultValueNotInChoices(context: "macros[0]", name: "___CHOICES___", value: "c", choices: ["a", "b"]),
                ]),
            ),
            TestCase(
                description: "detects invalid boolean default value",
                config: makeValidConfig(macros: [
                    Config.Macro(name: "___BOOL___", description: "desc", type: .boolean, default: "maybe"),
                ]),
                expected: .failure([
                    .booleanDefaultValueInvalid(context: "macros[0]", name: "___BOOL___", defaultValue: "maybe"),
                ]),
            ),
            TestCase(
                description: "detects invalid characters in path default value",
                config: makeValidConfig(macros: [
                    Config.Macro(name: "___PATH___", description: "desc", type: .path, default: "invalid\0path"),
                ]),
                expected: .failure([
                    .pathDefaultValueInvalidCharacters(context: "macros[0]", name: "___PATH___"),
                ]),
            ),
            TestCase(
                description: "detects invalid regex pattern in macro validation",
                config: makeValidConfig(macros: [
                    Config.Macro(name: "___REGEX___", description: "desc", type: .string, validate: "("),
                ]),
                expected: .failure([
                    .invalidRegexPattern(context: "macros[0]", name: "___REGEX___", pattern: "("),
                ]),
            ),
            TestCase(
                description: "detects default value not matching validation regex",
                config: makeValidConfig(macros: [
                    Config.Macro(name: "___REGEX___", description: "desc", type: .string, default: "123", validate: "^[a-z]+$"),
                ]),
                expected: .failure([
                    .defaultValueDoesNotMatchRegex(context: "macros[0]", name: "___REGEX___", defaultValue: "123", pattern: "^[a-z]+$"),
                ]),
            ),
            TestCase(
                description: "detects missing run or hatch in pre_hatch step",
                config: makeValidConfig(preHatch: [
                    Config.LifecycleStep(),
                ]),
                expected: .failure([
                    .lifecycleStepMissingRunOrHatch(context: "pre_hatch[0]"),
                ]),
            ),
            TestCase(
                description: "detects empty lifecycle step id",
                config: makeValidConfig(preHatch: [
                    Config.LifecycleStep(id: "", run: "echo ok"),
                ]),
                expected: .failure([
                    .lifecycleStepIdEmpty(context: "pre_hatch[0]"),
                ]),
            ),
            TestCase(
                description: "detects invalid characters in lifecycle step id",
                config: makeValidConfig(preHatch: [
                    Config.LifecycleStep(id: "invalid id", run: "echo ok"),
                ]),
                expected: .failure([
                    .lifecycleStepIdInvalidCharacters(context: "pre_hatch[0]", id: "invalid id"),
                ]),
            ),
            TestCase(
                description: "detects empty lifecycle step condition",
                config: makeValidConfig(preHatch: [
                    Config.LifecycleStep(if: "", run: "echo ok"),
                ]),
                expected: .failure([
                    .lifecycleStepConditionEmpty(context: "pre_hatch[0]"),
                ]),
            ),
            TestCase(
                description: "detects empty run command",
                config: makeValidConfig(preHatch: [
                    Config.LifecycleStep(run: ""),
                ]),
                expected: .failure([
                    .lifecycleStepMissingRunOrHatch(context: "pre_hatch[0]"),
                    .lifecycleStepRunEmpty(context: "pre_hatch[0]"),
                ]),
            ),
            TestCase(
                description: "detects empty hatch output",
                config: makeValidConfig(hatch: Config.HatchConfig(output: "")),
                expected: .failure([
                    .hatchOutputEmpty,
                ]),
            ),
            TestCase(
                description: "detects empty exclude path",
                config: makeValidConfig(hatch: Config.HatchConfig(
                    output: "output",
                    exclude: [.path("")],
                )),
                expected: .failure([
                    .excludePathEmpty(context: "hatch.exclude[0]"),
                ]),
            ),
            TestCase(
                description: "detects empty condition in conditional exclude",
                config: makeValidConfig(hatch: Config.HatchConfig(
                    output: "output",
                    exclude: [.conditional(Config.ConditionalExclude(if: "", paths: ["path"]))],
                )),
                expected: .failure([
                    .excludeConditionEmpty(context: "hatch.exclude[0]"),
                ]),
            ),
            TestCase(
                description: "detects missing paths in conditional exclude",
                config: makeValidConfig(hatch: Config.HatchConfig(
                    output: "output",
                    exclude: [.conditional(Config.ConditionalExclude(if: "true", paths: []))],
                )),
                expected: .failure([
                    .excludePathsEmpty(context: "hatch.exclude[0]"),
                ]),
            ),
            TestCase(
                description: "detects empty path entry in conditional exclude",
                config: makeValidConfig(hatch: Config.HatchConfig(
                    output: "output",
                    exclude: [.conditional(Config.ConditionalExclude(if: "true", paths: ["", "valid"]))],
                )),
                expected: .failure([
                    .excludeConditionalPathEmpty(context: "hatch.exclude[0]", pathIndex: 0),
                ]),
            ),
            TestCase(
                description: "detects undefined macro references in lifecycle steps",
                config: makeValidConfig(
                    macros: [
                        Config.Macro(name: "___DEFINED___", description: "desc"),
                    ],
                    preHatch: [
                        Config.LifecycleStep(run: "echo ___UNDEFINED___"),
                    ],
                ),
                expected: .failure([
                    .undefinedMacroReferenced(context: "pre_hatch[0].run", macroName: "___UNDEFINED___"),
                ]),
            ),
            TestCase(
                description: "detects duplicate lifecycle step ids",
                config: makeValidConfig(
                    preHatch: [
                        Config.LifecycleStep(id: "step", run: "echo 1"),
                        Config.LifecycleStep(id: "step", run: "echo 2"),
                    ],
                ),
                expected: .failure([
                    .duplicateStepId(context: "pre_hatch", index: 1, id: "step"),
                ]),
            ),
            TestCase(
                description: "detects invalid condition expression",
                config: makeValidConfig(preHatch: [
                    Config.LifecycleStep(if: "notDefinedFunction()", run: "echo ok"),
                ]),
                expected: .failure([
                    .invalidConditionExpression(context: "pre_hatch[0]", expression: "notDefinedFunction()"),
                ]),
            ),
            TestCase(
                description: "detects invalid condition expression",
                config: makeValidConfig(preHatch: [
                    Config.LifecycleStep(if: "process.exit(1)", run: "echo ok"),
                ]),
                expected: .failure([
                    .invalidConditionExpression(context: "pre_hatch[0]", expression: "process.exit(1)"),
                ]),
            ),
            TestCase(
                description: "aggregates multiple failures across sections",
                config: Config(
                    name: "/invalid",
                    description: "Valid description",
                    macros: [
                        Config.Macro(name: "", description: ""),
                    ],
                    preHatch: [
                        Config.LifecycleStep(run: ""),
                    ],
                    hatch: Config.HatchConfig(output: "output"),
                    postHatch: nil,
                ),
                expected: .failure([
                    .validationRuleError(ValidationError("Invalid directory name. Cannot contain '/' or start with whitespace.")),
                    .macroNameEmpty(context: "macros[0]"),
                    .macroDescriptionEmpty(context: "macros[0]"),
                    .lifecycleStepMissingRunOrHatch(context: "pre_hatch[0]"),
                    .lifecycleStepRunEmpty(context: "pre_hatch[0]"),
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

    private static func makeValidConfig(
        name: String = "ValidTemplate",
        description: String = "A valid description",
        macros: [Config.Macro] = [
            Config.Macro(name: "___NAME___", description: "desc"),
            Config.Macro(name: "___CHOICE___", description: "choice", type: .choice, default: "A", choices: ["A", "B"]),
        ],
        preHatch: [Config.LifecycleStep] = [
            Config.LifecycleStep(id: "pre", run: "echo pre"),
        ],
        hatch: Config.HatchConfig = Config.HatchConfig(output: "output"),
        postHatch: [Config.LifecycleStep] = [
            Config.LifecycleStep(id: "post", run: "echo post"),
        ],
    ) -> Config {
        Config(
            name: name,
            description: description,
            macros: macros,
            preHatch: preHatch,
            hatch: hatch,
            postHatch: postHatch,
        )
    }
}
