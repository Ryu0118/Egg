@testable import EggKit
import Foundation
import Testing
import Yams

/// Tests to verify that various config.yaml specifications can be decoded successfully
struct ConfigDecodingTests {
    let decoder = YAMLDecoder()

    @Test("decode config yaml", arguments: TestCase.allCases)
    func decodeConfigYaml(_ testCase: TestCase) throws {
        // Load YAML file from file system
        let fixtureURL = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("ConfigDecodingTests")
            .appendingPathComponent(testCase.filename)

        let yamlString = try String(contentsOf: fixtureURL, encoding: .utf8)

        // Attempt to decode
        let config = try decoder.decode(Config.self, from: yamlString)

        // Basic assertions to verify decode succeeded
        #expect(!config.name.isEmpty, "Config name should not be empty")
        #expect(!config.description.isEmpty, "Config description should not be empty")

        // Test-specific validations
        if let expectedMacroCount = testCase.expectedMacroCount {
            #expect((config.macros ?? []).count == expectedMacroCount)
        }
    }

    struct TestCase: CustomTestStringConvertible {
        let description: String
        let filename: String
        let expectedMacroCount: Int?

        static let allCases: [TestCase] = [
            TestCase(
                description: "minimal config with only required fields",
                filename: "minimal.yml",
                expectedMacroCount: nil,
            ),
            TestCase(
                description: "basic config with simple macros",
                filename: "basic_macros.yml",
                expectedMacroCount: 2,
            ),

            // Macro types
            TestCase(
                description: "string macro with validation regex",
                filename: "string_macro_with_validation.yml",
                expectedMacroCount: 1,
            ),
            TestCase(
                description: "boolean macro with default",
                filename: "boolean_macro.yml",
                expectedMacroCount: 1,
            ),
            TestCase(
                description: "choice macro with choices",
                filename: "choice_macro.yml",
                expectedMacroCount: 1,
            ),
            TestCase(
                description: "array macro with choices",
                filename: "array_macro.yml",
                expectedMacroCount: 1,
            ),
            TestCase(
                description: "path macro",
                filename: "path_macro.yml",
                expectedMacroCount: 1,
            ),

            // Lifecycle hooks
            TestCase(
                description: "pre_hatch with simple run command",
                filename: "pre_hatch_simple.yml",
                expectedMacroCount: nil,
            ),
            TestCase(
                description: "pre_hatch with id and step outputs",
                filename: "pre_hatch_with_id.yml",
                expectedMacroCount: nil,
            ),
            TestCase(
                description: "pre_hatch with conditional execution",
                filename: "pre_hatch_conditional.yml",
                expectedMacroCount: 1,
            ),
            TestCase(
                description: "post_hatch with multiple steps",
                filename: "post_hatch_multiple.yml",
                expectedMacroCount: nil,
            ),
            TestCase(
                description: "hatch with output only",
                filename: "hatch_output_only.yml",
                expectedMacroCount: nil,
            ),
            TestCase(
                description: "hatch with unconditional exclude",
                filename: "hatch_exclude_unconditional.yml",
                expectedMacroCount: nil,
            ),
            TestCase(
                description: "hatch with conditional exclude",
                filename: "hatch_exclude_conditional.yml",
                expectedMacroCount: 1,
            ),
            TestCase(
                description: "hatch with mixed exclude rules",
                filename: "hatch_exclude_mixed.yml",
                expectedMacroCount: 1,
            ),
            TestCase(
                description: "boolean condition",
                filename: "condition_boolean.yml",
                expectedMacroCount: 1,
            ),
            TestCase(
                description: "comparison condition",
                filename: "condition_comparison.yml",
                expectedMacroCount: 1,
            ),
            TestCase(
                description: "logical operators condition",
                filename: "condition_logical.yml",
                expectedMacroCount: 2,
            ),
            TestCase(
                description: "array includes condition",
                filename: "condition_array_includes.yml",
                expectedMacroCount: 1,
            ),
            TestCase(
                description: "step outputs condition",
                filename: "condition_step_outputs.yml",
                expectedMacroCount: nil,
            ),
            TestCase(
                description: "full featured config",
                filename: "full_featured.yml",
                expectedMacroCount: 6,
            ),
            TestCase(
                description: "multiple lifecycle steps with dependencies",
                filename: "lifecycle_dependencies.yml",
                expectedMacroCount: 2,
            ),
            TestCase(
                description: "config with version field",
                filename: "with_version.yml",
                expectedMacroCount: nil,
            ),
        ]

        var testDescription: String {
            description
        }
    }
}
