@testable import EggKit
import Foundation
import Testing

struct NativeTemplateEngineTests {
    let engine = NativeTemplateEngine()

    @Test(arguments: TestCase.allCases)
    func render(_ testCase: TestCase) async throws {
        let outputs = StepOutputsStorage()
        for output in testCase.stepOutputs {
            await outputs.store(phase: output.phase, stepId: output.stepId, outputs: output.values)
        }

        let context = TemplateContext(
            macros: testCase.macros,
            outputs: outputs,
            builtInMacroContext: testCase.builtInMacroContext
        )

        let result = try await engine.render(testCase.input, with: context)
        #expect(result == testCase.expectedOutput)
    }

    struct TestOutput {
        let phase: LifecyclePhase
        let stepId: String
        let values: [String: String]
    }

    struct TestCase: CustomTestStringConvertible {
        let description: String
        let input: String
        let macros: [ResolvedMacro]
        let stepOutputs: [TestOutput]
        let builtInMacroContext: BuiltInMacroContext
        let expectedOutput: String

        var testDescription: String { description }

        static let defaultContext = BuiltInMacroContext(
            outputDirectory: nil,
            workingDirectory: URL(filePath: "/tmp/work"),
            homeDirectory: URL(filePath: "/tmp/home"),
            currentDate: Date(timeIntervalSince1970: 0),
            environment: [:]
        )

        static let allCases: [TestCase] = [
            // MARK: - Macro substitution (___MACRO___)
            TestCase(
                description: "substitutes string macro",
                input: "Project: ___PROJECT_NAME___",
                macros: [
                    ResolvedMacro(name: "___PROJECT_NAME___", description: "", value: .string("MyApp")),
                ],
                stepOutputs: [],
                builtInMacroContext: defaultContext,
                expectedOutput: "Project: MyApp"
            ),
            TestCase(
                description: "substitutes boolean macro",
                input: "Debug: ___DEBUG___",
                macros: [
                    ResolvedMacro(name: "___DEBUG___", description: "", value: .boolean(true)),
                ],
                stepOutputs: [],
                builtInMacroContext: defaultContext,
                expectedOutput: "Debug: true"
            ),
            TestCase(
                description: "substitutes array macro as comma-separated",
                input: "Platforms: ___PLATFORMS___",
                macros: [
                    ResolvedMacro(name: "___PLATFORMS___", description: "", value: .array(["iOS", "macOS"])),
                ],
                stepOutputs: [],
                builtInMacroContext: defaultContext,
                expectedOutput: "Platforms: iOS, macOS"
            ),

            // MARK: - Step outputs (${{ phase.step.outputs.key }})
            TestCase(
                description: "substitutes step output reference",
                input: "v${{ pre_hatch.setup.outputs.version }}",
                macros: [],
                stepOutputs: [
                    TestOutput(phase: .preHatch, stepId: "setup", values: ["version": "1.0.0"]),
                ],
                builtInMacroContext: defaultContext,
                expectedOutput: "v1.0.0"
            ),
            TestCase(
                description: "substitutes post_hatch output",
                input: "URL: ${{ post_hatch.deploy.outputs.url }}",
                macros: [],
                stepOutputs: [
                    TestOutput(phase: .postHatch, stepId: "deploy", values: ["url": "https://example.com"]),
                ],
                builtInMacroContext: defaultContext,
                expectedOutput: "URL: https://example.com"
            ),

            // MARK: - Built-in macros
            TestCase(
                description: "substitutes built-in DATE macro",
                input: "Created: ___DATE___",
                macros: [],
                stepOutputs: [],
                builtInMacroContext: defaultContext,
                expectedOutput: "Created: " + BuiltInMacros.formatDate(Date(timeIntervalSince1970: 0), format: nil)
            ),

            // MARK: - Stencil syntax behavior
            // Note: Native engine still substitutes ___MACRO___ patterns even inside {{ }} and {% %}
            // This documents current behavior; the macros are replaced regardless of surrounding syntax
            TestCase(
                description: "substitutes macros inside Stencil variable syntax (current behavior)",
                input: "Name: {{ ___PROJECT_NAME___ }}",
                macros: [
                    ResolvedMacro(name: "___PROJECT_NAME___", description: "", value: .string("MyApp")),
                ],
                stepOutputs: [],
                builtInMacroContext: defaultContext,
                expectedOutput: "Name: {{ MyApp }}"
            ),
            TestCase(
                description: "substitutes macros inside Stencil control syntax (current behavior)",
                input: "{% if ___DEBUG___ %}debug{% endif %}",
                macros: [
                    ResolvedMacro(name: "___DEBUG___", description: "", value: .boolean(true)),
                ],
                stepOutputs: [],
                builtInMacroContext: defaultContext,
                expectedOutput: "{% if true %}debug{% endif %}"
            ),
            TestCase(
                description: "does not process Stencil step output syntax",
                input: "{{ pre_hatch.setup.outputs.version }}",
                macros: [],
                stepOutputs: [
                    TestOutput(phase: .preHatch, stepId: "setup", values: ["version": "1.0.0"]),
                ],
                builtInMacroContext: defaultContext,
                expectedOutput: "{{ pre_hatch.setup.outputs.version }}"
            ),
        ]
    }
}
