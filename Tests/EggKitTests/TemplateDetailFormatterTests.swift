@testable import EggKit
import Foundation
import Testing

struct TemplateDetailFormatterTests {
    let formatter = TemplateDetailFormatter()

    // MARK: - generateExampleValue Tests

    @Test(arguments: GenerateExampleValueTestCase.allCases)
    func generateExampleValue(_ testCase: GenerateExampleValueTestCase) {
        let result = formatter.generateExampleValue(for: testCase.macro)
        #expect(result == testCase.expected)
    }

    struct GenerateExampleValueTestCase: CustomTestStringConvertible {
        let description: String
        let macro: Config.Macro
        let expected: String

        var testDescription: String { description }

        static let allCases: [GenerateExampleValueTestCase] = [
            // String type
            GenerateExampleValueTestCase(
                description: "string with default returns default",
                macro: Config.Macro(
                    name: "___NAME___",
                    description: "A name",
                    type: .string,
                    default: "DefaultValue"
                ),
                expected: "DefaultValue"
            ),
            GenerateExampleValueTestCase(
                description: "string without default returns placeholder",
                macro: Config.Macro(
                    name: "___NAME___",
                    description: "A name",
                    type: .string
                ),
                expected: "value"
            ),
            // Boolean type
            GenerateExampleValueTestCase(
                description: "boolean with default returns default",
                macro: Config.Macro(
                    name: "___ENABLED___",
                    description: "Enable feature",
                    type: .boolean,
                    default: "false"
                ),
                expected: "false"
            ),
            GenerateExampleValueTestCase(
                description: "boolean without default returns true",
                macro: Config.Macro(
                    name: "___ENABLED___",
                    description: "Enable feature",
                    type: .boolean
                ),
                expected: "true"
            ),
            // Choice type
            GenerateExampleValueTestCase(
                description: "choice with choices returns first choice",
                macro: Config.Macro(
                    name: "___PLATFORM___",
                    description: "Target platform",
                    type: .choice,
                    choices: ["iOS", "macOS", "tvOS"]
                ),
                expected: "iOS"
            ),
            GenerateExampleValueTestCase(
                description: "choice without choices returns placeholder",
                macro: Config.Macro(
                    name: "___PLATFORM___",
                    description: "Target platform",
                    type: .choice
                ),
                expected: "option"
            ),
            // Choices type
            GenerateExampleValueTestCase(
                description: "choices with choices returns first two",
                macro: Config.Macro(
                    name: "___PLATFORMS___",
                    description: "Target platforms",
                    type: .choices,
                    choices: ["iOS", "macOS", "tvOS"]
                ),
                expected: "iOS macOS"
            ),
            GenerateExampleValueTestCase(
                description: "choices with single choice returns it",
                macro: Config.Macro(
                    name: "___PLATFORMS___",
                    description: "Target platforms",
                    type: .choices,
                    choices: ["iOS"]
                ),
                expected: "iOS"
            ),
            GenerateExampleValueTestCase(
                description: "choices without choices returns placeholder",
                macro: Config.Macro(
                    name: "___PLATFORMS___",
                    description: "Target platforms",
                    type: .choices
                ),
                expected: "option1 option2"
            ),
            GenerateExampleValueTestCase(
                description: "choices with JSON array default returns space-separated",
                macro: Config.Macro(
                    name: "___PLATFORMS___",
                    description: "Target platforms",
                    type: .choices,
                    default: "[\"iOS\",\"macOS\"]"
                ),
                expected: "iOS macOS"
            ),
            // Array type
            GenerateExampleValueTestCase(
                description: "array with JSON array default returns space-separated",
                macro: Config.Macro(
                    name: "___PLATFORMS___",
                    description: "Target platforms",
                    type: .array,
                    default: "[\"iOS18\",\"iPadOS18\",\"macOS15\"]"
                ),
                expected: "iOS18 iPadOS18 macOS15"
            ),
            GenerateExampleValueTestCase(
                description: "array with space-separated default returns as-is",
                macro: Config.Macro(
                    name: "___MODULES___",
                    description: "Module names",
                    type: .array,
                    default: "Core UI Network"
                ),
                expected: "Core UI Network"
            ),
            GenerateExampleValueTestCase(
                description: "array without default returns placeholder",
                macro: Config.Macro(
                    name: "___MODULES___",
                    description: "Module names",
                    type: .array
                ),
                expected: "item1 item2"
            ),
            // Path type
            GenerateExampleValueTestCase(
                description: "path with default returns default",
                macro: Config.Macro(
                    name: "___OUTPUT___",
                    description: "Output path",
                    type: .path,
                    default: "~/Projects"
                ),
                expected: "~/Projects"
            ),
            GenerateExampleValueTestCase(
                description: "path without default returns placeholder",
                macro: Config.Macro(
                    name: "___OUTPUT___",
                    description: "Output path",
                    type: .path
                ),
                expected: "./path/to/file"
            ),
        ]
    }

    // MARK: - generateExampleCommand Tests

    @Test(arguments: GenerateExampleCommandTestCase.allCases)
    func generateExampleCommand(_ testCase: GenerateExampleCommandTestCase) {
        let result = formatter.generateExampleCommand(
            templateName: testCase.templateName,
            macros: testCase.macros
        )
        #expect(result == testCase.expected)
    }

    struct GenerateExampleCommandTestCase: CustomTestStringConvertible {
        let description: String
        let templateName: String
        let macros: [Config.Macro]?
        let expected: String

        var testDescription: String { description }

        static let allCases: [GenerateExampleCommandTestCase] = [
            GenerateExampleCommandTestCase(
                description: "no macros returns basic command",
                templateName: "MyTemplate",
                macros: nil,
                expected: "egg hatch MyTemplate"
            ),
            GenerateExampleCommandTestCase(
                description: "empty macros returns basic command",
                templateName: "MyTemplate",
                macros: [],
                expected: "egg hatch MyTemplate"
            ),
            GenerateExampleCommandTestCase(
                description: "template name with spaces is quoted",
                templateName: "My Template Name",
                macros: nil,
                expected: "egg hatch \"My Template Name\""
            ),
            GenerateExampleCommandTestCase(
                description: "template name with spaces and macros",
                templateName: "iOS App Template",
                macros: [
                    Config.Macro(
                        name: "___NAME___",
                        description: "App name",
                        type: .string,
                        default: "MyApp"
                    ),
                ],
                expected: "egg hatch \"iOS App Template\" --name \"MyApp\""
            ),
            GenerateExampleCommandTestCase(
                description: "single string macro with default",
                templateName: "iOSTemplate",
                macros: [
                    Config.Macro(
                        name: "___APP_NAME___",
                        description: "Application name",
                        type: .string,
                        default: "MyApp"
                    ),
                ],
                expected: "egg hatch iOSTemplate --app-name \"MyApp\""
            ),
            GenerateExampleCommandTestCase(
                description: "boolean macro true",
                templateName: "iOSTemplate",
                macros: [
                    Config.Macro(
                        name: "___USE_SWIFT_UI___",
                        description: "Use SwiftUI",
                        type: .boolean,
                        default: "true"
                    ),
                ],
                expected: "egg hatch iOSTemplate --use-swift-ui"
            ),
            GenerateExampleCommandTestCase(
                description: "boolean macro false",
                templateName: "iOSTemplate",
                macros: [
                    Config.Macro(
                        name: "___USE_SWIFT_UI___",
                        description: "Use SwiftUI",
                        type: .boolean,
                        default: "false"
                    ),
                ],
                expected: "egg hatch iOSTemplate --no-use-swift-ui"
            ),
            GenerateExampleCommandTestCase(
                description: "choice macro",
                templateName: "Template",
                macros: [
                    Config.Macro(
                        name: "___PLATFORM___",
                        description: "Platform",
                        type: .choice,
                        choices: ["iOS", "macOS"]
                    ),
                ],
                expected: "egg hatch Template --platform \"iOS\""
            ),
            GenerateExampleCommandTestCase(
                description: "choices macro",
                templateName: "Template",
                macros: [
                    Config.Macro(
                        name: "___PLATFORMS___",
                        description: "Platforms",
                        type: .choices,
                        choices: ["iOS", "macOS", "tvOS"]
                    ),
                ],
                expected: "egg hatch Template --platforms iOS macOS"
            ),
            GenerateExampleCommandTestCase(
                description: "multiple macros",
                templateName: "iOSTemplate",
                macros: [
                    Config.Macro(
                        name: "___APP_NAME___",
                        description: "App name",
                        type: .string,
                        default: "MyApp"
                    ),
                    Config.Macro(
                        name: "___USE_SWIFT_UI___",
                        description: "Use SwiftUI",
                        type: .boolean,
                        default: "true"
                    ),
                    Config.Macro(
                        name: "___PLATFORM___",
                        description: "Platform",
                        type: .choice,
                        choices: ["iOS", "macOS"]
                    ),
                ],
                expected: "egg hatch iOSTemplate --app-name \"MyApp\" --use-swift-ui --platform \"iOS\""
            ),
        ]
    }

    // MARK: - format Tests

    @Test(arguments: FormatTestCase.allCases)
    func format(_ testCase: FormatTestCase) {
        let result = formatter.format(template: testCase.template, location: testCase.location)
        #expect(result.basicInfo.name == testCase.expectedBasicInfo.name)
        #expect(result.basicInfo.description == testCase.expectedBasicInfo.description)
        #expect(result.basicInfo.version == testCase.expectedBasicInfo.version)
        #expect(result.basicInfo.locationName == testCase.expectedBasicInfo.locationName)
        #expect(result.macros.count == testCase.expectedMacroCount)
        #expect(result.exampleCommand == testCase.expectedExampleCommand)
    }

    struct FormatTestCase: CustomTestStringConvertible {
        let description: String
        let template: Template
        let location: TemplateLocationType
        let expectedBasicInfo: (name: String, description: String, version: String?, locationName: String)
        let expectedMacroCount: Int
        let expectedExampleCommand: String

        var testDescription: String { description }

        static let allCases: [FormatTestCase] = [
            FormatTestCase(
                description: "basic template with macros",
                template: Template(
                    path: URL(filePath: "/path/to/template"),
                    config: Config(
                        name: "TestTemplate",
                        description: "A test template",
                        version: "1.0.0",
                        macros: [
                            Config.Macro(
                                name: "___NAME___",
                                description: "Project name",
                                type: .string,
                                default: "MyProject",
                                validate: "^[A-Za-z]+$"
                            ),
                        ],
                        hatch: .init(output: "./output")
                    ),
                    isValid: true
                ),
                location: .global,
                expectedBasicInfo: (
                    name: "TestTemplate",
                    description: "A test template",
                    version: "1.0.0",
                    locationName: "global"
                ),
                expectedMacroCount: 1,
                expectedExampleCommand: "egg hatch TestTemplate --name \"MyProject\""
            ),
            FormatTestCase(
                description: "template without macros",
                template: Template(
                    path: URL(filePath: "/path/to/template"),
                    config: Config(
                        name: "SimpleTemplate",
                        description: "A simple template",
                        hatch: .init(output: "./output")
                    ),
                    isValid: true
                ),
                location: .global,
                expectedBasicInfo: (
                    name: "SimpleTemplate",
                    description: "A simple template",
                    version: nil,
                    locationName: "global"
                ),
                expectedMacroCount: 0,
                expectedExampleCommand: "egg hatch SimpleTemplate"
            ),
            FormatTestCase(
                description: "template with choice macro",
                template: Template(
                    path: URL(filePath: "/path/to/template"),
                    config: Config(
                        name: "ChoiceTemplate",
                        description: "Template with choice",
                        macros: [
                            Config.Macro(
                                name: "___STYLE___",
                                description: "UI Style",
                                type: .choice,
                                choices: ["UIKit", "SwiftUI", "AppKit"]
                            ),
                        ],
                        hatch: .init(output: "./output")
                    ),
                    isValid: true
                ),
                location: .global,
                expectedBasicInfo: (
                    name: "ChoiceTemplate",
                    description: "Template with choice",
                    version: nil,
                    locationName: "global"
                ),
                expectedMacroCount: 1,
                expectedExampleCommand: "egg hatch ChoiceTemplate --style \"UIKit\""
            ),
        ]
    }
}
