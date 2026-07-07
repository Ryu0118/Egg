@testable import EggKit
import Foundation
import Testing

struct ParsedMacroDefinitionValidatorTests {
    @Test(arguments: TestCase.allCases)
    func validate(_ testCase: TestCase) async throws {
        let workingDirectory = URL(filePath: "/tmp/test")
        let homeDirectory = URL(filePath: "/Users/testuser")
        let validator = ParsedMacroDefinitionValidator(
            config: testCase.config,
            workingDirectory: workingDirectory,
            homeDirectory: homeDirectory,
        )

        switch testCase.expected {
        case let .success(expectedMacros):
            let result = try await validator.validate(testCase.parsedMacros)
            #expect(result == expectedMacros)
        case let .failure(expectedErrors):
            do {
                _ = try await validator.validate(testCase.parsedMacros)
                #expect(Bool(false), "Expected errors \(expectedErrors)")
            } catch {
                guard let combinedError = error as? CombinedError else {
                    throw error
                }

                let actualErrors = combinedError.errors
                    .compactMap { $0 as? ParsedMacroDefinitionValidator.Error }
                #expect(actualErrors == expectedErrors)
            }
        }
    }

    struct TestCase: CustomTestStringConvertible {
        let description: String
        let config: Config
        let parsedMacros: [ParsedMacroDefinition]
        let expected: Result

        static let allCases: [TestCase] = [
            TestCase(
                description: "validates string macro",
                config: Config(
                    name: "Test",
                    description: "Test",
                    macros: [
                        Config.Macro(name: "___NAME___", description: "Name", type: .string),
                    ],

                    hatch: Config.HatchConfig(output: "."),
                ),
                parsedMacros: [
                    ParsedMacroDefinition(macro: "___NAME___", values: ["TestValue"]),
                ],
                expected: .success([
                    ResolvedMacro(name: "___NAME___", description: "Name", value: .string("TestValue")),
                ]),
            ),
            TestCase(
                description: "validates boolean macro with true value",
                config: Config(
                    name: "Test",
                    description: "Test",
                    macros: [
                        Config.Macro(name: "___ENABLED___", description: "Enabled", type: .boolean),
                    ],

                    hatch: Config.HatchConfig(output: "."),
                ),
                parsedMacros: [
                    ParsedMacroDefinition(macro: "___ENABLED___", values: ["true"]),
                ],
                expected: .success([
                    ResolvedMacro(name: "___ENABLED___", description: "Enabled", value: .boolean(true)),
                ]),
            ),
            TestCase(
                description: "validates boolean macro with false value",
                config: Config(
                    name: "Test",
                    description: "Test",
                    macros: [
                        Config.Macro(name: "___ENABLED___", description: "Enabled", type: .boolean),
                    ],

                    hatch: Config.HatchConfig(output: "."),
                ),
                parsedMacros: [
                    ParsedMacroDefinition(macro: "___ENABLED___", values: ["false"]),
                ],
                expected: .success([
                    ResolvedMacro(name: "___ENABLED___", description: "Enabled", value: .boolean(false)),
                ]),
            ),
            TestCase(
                description: "validates choice macro",
                config: Config(
                    name: "Test",
                    description: "Test",
                    macros: [
                        Config.Macro(name: "___TYPE___", description: "Type", type: .choice, choices: ["A", "B", "C"]),
                    ],

                    hatch: Config.HatchConfig(output: "."),
                ),
                parsedMacros: [
                    ParsedMacroDefinition(macro: "___TYPE___", values: ["B"]),
                ],
                expected: .success([
                    ResolvedMacro(name: "___TYPE___", description: "Type", value: .choice("B")),
                ]),
            ),
            TestCase(
                description: "validates array macro",
                config: Config(
                    name: "Test",
                    description: "Test",
                    macros: [
                        Config.Macro(name: "___PLATFORMS___", description: "Platforms", type: .array),
                    ],

                    hatch: Config.HatchConfig(output: "."),
                ),
                parsedMacros: [
                    ParsedMacroDefinition(macro: "___PLATFORMS___", values: ["iOS", "macOS", "watchOS"]),
                ],
                expected: .success([
                    ResolvedMacro(name: "___PLATFORMS___", description: "Platforms", value: .array(["iOS", "macOS", "watchOS"])),
                ]),
            ),
            TestCase(
                description: "validates path macro with absolute path",
                config: Config(
                    name: "Test",
                    description: "Test",
                    macros: [
                        Config.Macro(name: "___PATH___", description: "Path", type: .path),
                    ],

                    hatch: Config.HatchConfig(output: "."),
                ),
                parsedMacros: [
                    ParsedMacroDefinition(macro: "___PATH___", values: ["/absolute/path/to/file"]),
                ],
                expected: .success([
                    ResolvedMacro(name: "___PATH___", description: "Path", value: .path(URL(filePath: "/absolute/path/to/file"))),
                ]),
            ),
            TestCase(
                description: "validates path macro with relative path",
                config: Config(
                    name: "Test",
                    description: "Test",
                    macros: [
                        Config.Macro(name: "___PATH___", description: "Path", type: .path),
                    ],

                    hatch: Config.HatchConfig(output: "."),
                ),
                parsedMacros: [
                    ParsedMacroDefinition(macro: "___PATH___", values: ["relative/path"]),
                ],
                expected: .success([
                    ResolvedMacro(name: "___PATH___", description: "Path", value: .path(URL(filePath: "/tmp/test").appending(path: "relative/path"))),
                ]),
            ),
            TestCase(
                description: "uses default value when macro is not provided",
                config: Config(
                    name: "Test",
                    description: "Test",
                    macros: [
                        Config.Macro(name: "___NAME___", description: "Name", type: .string, default: "DefaultName"),
                        Config.Macro(name: "___ENABLED___", description: "Enabled", type: .boolean, default: "true"),
                    ],

                    hatch: Config.HatchConfig(output: "."),
                ),
                parsedMacros: [],
                expected: .success([
                    ResolvedMacro(name: "___NAME___", description: "Name", value: .string("DefaultName")),
                    ResolvedMacro(name: "___ENABLED___", description: "Enabled", value: .boolean(true)),
                ]),
            ),
            TestCase(
                description: "prioritizes provided value over default",
                config: Config(
                    name: "Test",
                    description: "Test",
                    macros: [
                        Config.Macro(name: "___NAME___", description: "Name", type: .string, default: "DefaultName"),
                    ],

                    hatch: Config.HatchConfig(output: "."),
                ),
                parsedMacros: [
                    ParsedMacroDefinition(macro: "___NAME___", values: ["ProvidedName"]),
                ],
                expected: .success([
                    ResolvedMacro(name: "___NAME___", description: "Name", value: .string("ProvidedName")),
                ]),
            ),
            TestCase(
                description: "combines provided and default macros",
                config: Config(
                    name: "Test",
                    description: "Test",
                    macros: [
                        Config.Macro(name: "___NAME___", description: "Name", type: .string, default: "DefaultName"),
                        Config.Macro(name: "___TYPE___", description: "Type", type: .choice, default: "A", choices: ["A", "B"]),
                    ],

                    hatch: Config.HatchConfig(output: "."),
                ),
                parsedMacros: [
                    ParsedMacroDefinition(macro: "___NAME___", values: ["CustomName"]),
                ],
                expected: .success([
                    ResolvedMacro(name: "___NAME___", description: "Name", value: .string("CustomName")),
                    ResolvedMacro(name: "___TYPE___", description: "Type", value: .choice("A")),
                ]),
            ),
            TestCase(
                description: "validates value matching regex pattern",
                config: Config(
                    name: "Test",
                    description: "Test",
                    macros: [
                        Config.Macro(name: "___NAME___", description: "Name", type: .string, validate: "^[A-Z][a-zA-Z0-9]*$"),
                    ],

                    hatch: Config.HatchConfig(output: "."),
                ),
                parsedMacros: [
                    ParsedMacroDefinition(macro: "___NAME___", values: ["MyModule"]),
                ],
                expected: .success([
                    ResolvedMacro(name: "___NAME___", description: "Name", value: .string("MyModule")),
                ]),
            ),
            TestCase(
                description: "fails when macro is not defined in config",
                config: Config(
                    name: "Test",
                    description: "Test",
                    macros: [
                        Config.Macro(name: "___DEFINED___", description: "Defined", type: .string, default: "default"),
                    ],

                    hatch: Config.HatchConfig(output: "."),
                ),
                parsedMacros: [
                    ParsedMacroDefinition(macro: "___UNDEFINED___", values: ["value"]),
                ],
                expected: .failure([
                    .unknownMacro(macro: "___UNDEFINED___"),
                ]),
            ),
            TestCase(
                description: "fails when array macro has no values",
                config: Config(
                    name: "Test",
                    description: "Test",
                    macros: [
                        Config.Macro(name: "___ARRAY___", description: "Array", type: .array),
                    ],

                    hatch: Config.HatchConfig(output: "."),
                ),
                parsedMacros: [
                    ParsedMacroDefinition(macro: "___ARRAY___", values: []),
                ],
                expected: .failure([
                    .arrayRequiresAtLeastOneValue(macro: "___ARRAY___"),
                ]),
            ),
            TestCase(
                description: "fails when string macro has multiple values",
                config: Config(
                    name: "Test",
                    description: "Test",
                    macros: [
                        Config.Macro(name: "___NAME___", description: "Name", type: .string),
                    ],

                    hatch: Config.HatchConfig(output: "."),
                ),
                parsedMacros: [
                    ParsedMacroDefinition(macro: "___NAME___", values: ["value1", "value2"]),
                ],
                expected: .failure([
                    .nonArrayRequiresSingleValue(macro: "___NAME___", type: .string, actualCount: 2),
                ]),
            ),
            TestCase(
                description: "fails when boolean macro has multiple values",
                config: Config(
                    name: "Test",
                    description: "Test",
                    macros: [
                        Config.Macro(name: "___ENABLED___", description: "Enabled", type: .boolean),
                    ],

                    hatch: Config.HatchConfig(output: "."),
                ),
                parsedMacros: [
                    ParsedMacroDefinition(macro: "___ENABLED___", values: ["true", "false"]),
                ],
                expected: .failure([
                    .nonArrayRequiresSingleValue(macro: "___ENABLED___", type: .boolean, actualCount: 2),
                ]),
            ),
            TestCase(
                description: "fails when choice macro has no choices defined",
                config: Config(
                    name: "Test",
                    description: "Test",
                    macros: [
                        Config.Macro(name: "___TYPE___", description: "Type", type: .choice, choices: nil),
                    ],

                    hatch: Config.HatchConfig(output: "."),
                ),
                parsedMacros: [
                    ParsedMacroDefinition(macro: "___TYPE___", values: ["A"]),
                ],
                expected: .failure([
                    .choiceTypeRequiresChoices(macro: "___TYPE___"),
                ]),
            ),
            TestCase(
                description: "fails when choice value is not in allowed choices",
                config: Config(
                    name: "Test",
                    description: "Test",
                    macros: [
                        Config.Macro(name: "___TYPE___", description: "Type", type: .choice, choices: ["A", "B"]),
                    ],

                    hatch: Config.HatchConfig(output: "."),
                ),
                parsedMacros: [
                    ParsedMacroDefinition(macro: "___TYPE___", values: ["C"]),
                ],
                expected: .failure([
                    .valueNotInChoices(macro: "___TYPE___", value: "C", choices: ["A", "B"]),
                ]),
            ),

            // Error cases - regex validation
            TestCase(
                description: "fails when value does not match regex pattern",
                config: Config(
                    name: "Test",
                    description: "Test",
                    macros: [
                        Config.Macro(name: "___NAME___", description: "Name", type: .string, validate: "^[A-Z][a-zA-Z0-9]*$"),
                    ],

                    hatch: Config.HatchConfig(output: "."),
                ),
                parsedMacros: [
                    ParsedMacroDefinition(macro: "___NAME___", values: ["invalid-name"]),
                ],
                expected: .failure([
                    .valueDoesNotMatchRegex(macro: "___NAME___", value: "invalid-name", pattern: "^[A-Z][a-zA-Z0-9]*$"),
                ]),
            ),

            // Array validation tests
            TestCase(
                description: "validates array elements with regex pattern",
                config: Config(
                    name: "Test",
                    description: "Test",
                    macros: [
                        Config.Macro(
                            name: "___MODULES___",
                            description: "Modules",
                            type: .array,
                            validate: "^[A-Z][a-zA-Z0-9]*$",
                        ),
                    ],
                    hatch: Config.HatchConfig(output: "."),
                ),
                parsedMacros: [
                    ParsedMacroDefinition(macro: "___MODULES___", values: ["ModuleA", "ModuleB", "ModuleC"]),
                ],
                expected: .success([
                    ResolvedMacro(
                        name: "___MODULES___",
                        description: "Modules",
                        value: .array(["ModuleA", "ModuleB", "ModuleC"]),
                    ),
                ]),
            ),
            TestCase(
                description: "fails when one array element does not match regex pattern",
                config: Config(
                    name: "Test",
                    description: "Test",
                    macros: [
                        Config.Macro(
                            name: "___MODULES___",
                            description: "Modules",
                            type: .array,
                            validate: "^[A-Z][a-zA-Z0-9]*$",
                        ),
                    ],
                    hatch: Config.HatchConfig(output: "."),
                ),
                parsedMacros: [
                    ParsedMacroDefinition(macro: "___MODULES___", values: ["ModuleA", "invalid-module", "ModuleC"]),
                ],
                expected: .failure([
                    .valueDoesNotMatchRegex(
                        macro: "___MODULES___",
                        value: "invalid-module",
                        pattern: "^[A-Z][a-zA-Z0-9]*$",
                    ),
                ]),
            ),
            TestCase(
                description: "validates single element array",
                config: Config(
                    name: "Test",
                    description: "Test",
                    macros: [
                        Config.Macro(
                            name: "___MODULES___",
                            description: "Modules",
                            type: .array,
                            validate: "^[A-Z][a-zA-Z0-9]*$",
                        ),
                    ],
                    hatch: Config.HatchConfig(output: "."),
                ),
                parsedMacros: [
                    ParsedMacroDefinition(macro: "___MODULES___", values: ["SingleModule"]),
                ],
                expected: .success([
                    ResolvedMacro(
                        name: "___MODULES___",
                        description: "Modules",
                        value: .array(["SingleModule"]),
                    ),
                ]),
            ),
            TestCase(
                description: "validates array with format and regex",
                config: Config(
                    name: "Test",
                    description: "Test",
                    macros: [
                        Config.Macro(
                            name: "___PACKAGES___",
                            description: "Packages",
                            type: .array,
                            validate: "^[a-z][a-z0-9-]*$",
                        ),
                    ],
                    hatch: Config.HatchConfig(output: "."),
                ),
                parsedMacros: [
                    ParsedMacroDefinition(macro: "___PACKAGES___", values: ["package-a", "package-b"]),
                ],
                expected: .success([
                    ResolvedMacro(
                        name: "___PACKAGES___",
                        description: "Packages",
                        value: .array(["package-a", "package-b"]),
                    ),
                ]),
            ),

            // Error cases - conversion
            TestCase(
                description: "fails when boolean value is invalid",
                config: Config(
                    name: "Test",
                    description: "Test",
                    macros: [
                        Config.Macro(name: "___ENABLED___", description: "Enabled", type: .boolean),
                    ],

                    hatch: Config.HatchConfig(output: "."),
                ),
                parsedMacros: [
                    ParsedMacroDefinition(macro: "___ENABLED___", values: ["maybe"]),
                ],
                expected: .failure([
                    .conversionFailed(macro: "___ENABLED___", type: .boolean),
                ]),
            ),
            TestCase(
                description: "fails when path value is empty",
                config: Config(
                    name: "Test",
                    description: "Test",
                    macros: [
                        Config.Macro(name: "___PATH___", description: "Path", type: .path),
                    ],

                    hatch: Config.HatchConfig(output: "."),
                ),
                parsedMacros: [
                    ParsedMacroDefinition(macro: "___PATH___", values: [""]),
                ],
                expected: .failure([
                    .conversionFailed(macro: "___PATH___", type: .path),
                ]),
            ),
            TestCase(
                description: "validates path macro with tilde expansion",
                config: Config(
                    name: "Test",
                    description: "Test",
                    macros: [
                        Config.Macro(name: "___PATH___", description: "Path", type: .path),
                    ],

                    hatch: Config.HatchConfig(output: "."),
                ),
                parsedMacros: [
                    ParsedMacroDefinition(macro: "___PATH___", values: ["~/path/to/file"]),
                ],
                expected: .success([
                    ResolvedMacro(name: "___PATH___", description: "Path", value: .path(URL(filePath: "/Users/testuser/path/to/file"))),
                ]),
            ),
            TestCase(
                description: "validates path macro with tilde only",
                config: Config(
                    name: "Test",
                    description: "Test",
                    macros: [
                        Config.Macro(name: "___PATH___", description: "Path", type: .path),
                    ],

                    hatch: Config.HatchConfig(output: "."),
                ),
                parsedMacros: [
                    ParsedMacroDefinition(macro: "___PATH___", values: ["~"]),
                ],
                expected: .success([
                    ResolvedMacro(name: "___PATH___", description: "Path", value: .path(URL(filePath: "/Users/testuser"))),
                ]),
            ),
            TestCase(
                description: "fails when required macro is not provided",
                config: Config(
                    name: "Test",
                    description: "Test",
                    macros: [
                        Config.Macro(name: "___REQUIRED___", description: "Required", type: .string),
                    ],

                    hatch: Config.HatchConfig(output: "."),
                ),
                parsedMacros: [],
                expected: .failure([
                    .requiredMacroNotProvided(macro: "___REQUIRED___"),
                ]),
            ),
            TestCase(
                description: "fails when multiple required macros are not provided",
                config: Config(
                    name: "Test",
                    description: "Test",
                    macros: [
                        Config.Macro(name: "___REQUIRED1___", description: "Required 1", type: .string),
                        Config.Macro(name: "___REQUIRED2___", description: "Required 2", type: .boolean),
                    ],

                    hatch: Config.HatchConfig(output: "."),
                ),
                parsedMacros: [],
                expected: .failure([
                    .requiredMacroNotProvided(macro: "___REQUIRED1___"),
                    .requiredMacroNotProvided(macro: "___REQUIRED2___"),
                ]),
            ),
            TestCase(
                description: "succeeds when required macro is provided",
                config: Config(
                    name: "Test",
                    description: "Test",
                    macros: [
                        Config.Macro(name: "___REQUIRED___", description: "Required", type: .string),
                    ],

                    hatch: Config.HatchConfig(output: "."),
                ),
                parsedMacros: [
                    ParsedMacroDefinition(macro: "___REQUIRED___", values: ["value"]),
                ],
                expected: .success([
                    ResolvedMacro(name: "___REQUIRED___", description: "Required", value: .string("value")),
                ]),
            ),
            TestCase(
                description: "combines required and optional macros correctly",
                config: Config(
                    name: "Test",
                    description: "Test",
                    macros: [
                        Config.Macro(name: "___REQUIRED___", description: "Required", type: .string),
                        Config.Macro(name: "___OPTIONAL___", description: "Optional", type: .string, default: "default"),
                    ],

                    hatch: Config.HatchConfig(output: "."),
                ),
                parsedMacros: [
                    ParsedMacroDefinition(macro: "___REQUIRED___", values: ["value"]),
                ],
                expected: .success([
                    ResolvedMacro(name: "___REQUIRED___", description: "Required", value: .string("value")),
                    ResolvedMacro(name: "___OPTIONAL___", description: "Optional", value: .string("default")),
                ]),
            ),
            TestCase(
                description: "aggregates multiple validation errors",
                config: Config(
                    name: "Test",
                    description: "Test",
                    macros: [
                        Config.Macro(name: "___NAME___", description: "Name", type: .string, validate: "^[A-Z]"),
                        Config.Macro(name: "___TYPE___", description: "Type", type: .choice, choices: ["A", "B"]),
                    ],

                    hatch: Config.HatchConfig(output: "."),
                ),
                parsedMacros: [
                    ParsedMacroDefinition(macro: "___NAME___", values: ["invalid"]),
                    ParsedMacroDefinition(macro: "___TYPE___", values: ["C"]),
                ],
                expected: .failure([
                    .valueDoesNotMatchRegex(macro: "___NAME___", value: "invalid", pattern: "^[A-Z]"),
                    .valueNotInChoices(macro: "___TYPE___", value: "C", choices: ["A", "B"]),
                ]),
            ),
            TestCase(
                description: "validates path macro with root path",
                config: Config(
                    name: "Test",
                    description: "Test",
                    macros: [
                        Config.Macro(name: "___PATH___", description: "Path", type: .path),
                    ],

                    hatch: Config.HatchConfig(output: "."),
                ),
                parsedMacros: [
                    ParsedMacroDefinition(macro: "___PATH___", values: ["/"]),
                ],
                expected: .success([
                    ResolvedMacro(name: "___PATH___", description: "Path", value: .path(URL(filePath: "/"))),
                ]),
            ),
            TestCase(
                description: "validates path macro with dot resolves to working directory",
                config: Config(
                    name: "Test",
                    description: "Test",
                    macros: [
                        Config.Macro(name: "___PATH___", description: "Path", type: .path),
                    ],

                    hatch: Config.HatchConfig(output: "."),
                ),
                parsedMacros: [
                    ParsedMacroDefinition(macro: "___PATH___", values: ["."]),
                ],
                expected: .success([
                    // URL(filePath:) with directory resolves to path with trailing slash
                    ResolvedMacro(name: "___PATH___", description: "Path", value: .path(URL(filePath: "/tmp/test/"))),
                ]),
            ),
        ]

        enum Result {
            case success([ResolvedMacro])
            case failure([ParsedMacroDefinitionValidator.Error])
        }

        var testDescription: String {
            description
        }
    }
}
