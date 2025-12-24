@testable import EggKit
import Foundation
import Testing

struct StencilTemplateEngineTests {
    let engine = StencilTemplateEngine()

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

        switch testCase.expectation {
        case let .success(expected):
            let result = try await engine.render(testCase.input, with: context)
            #expect(result == expected)
        case .syntaxError:
            await #expect(throws: StencilTemplateEngine.Error.self) {
                _ = try await engine.render(testCase.input, with: context)
            }
        }
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
        let expectation: Expectation

        var testDescription: String { description }

        enum Expectation {
            case success(String)
            case syntaxError
        }

        static let defaultContext = BuiltInMacroContext(
            outputDirectory: nil,
            workingDirectory: URL(filePath: "/tmp/work"),
            homeDirectory: URL(filePath: "/tmp/home"),
            currentDate: Date(timeIntervalSince1970: 0),
            environment: [:]
        )

        static let allCases: [TestCase] = [
            // MARK: - Basic variable output
            TestCase(
                description: "renders string macro",
                input: "Project: {{ ___PROJECT_NAME___ }}",
                macros: [
                    ResolvedMacro(name: "___PROJECT_NAME___", description: "", value: .string("MyApp")),
                ],
                stepOutputs: [],
                builtInMacroContext: defaultContext,
                expectation: .success("Project: MyApp")
            ),
            TestCase(
                description: "renders boolean macro as value",
                input: "Debug: {{ ___DEBUG___ }}",
                macros: [
                    ResolvedMacro(name: "___DEBUG___", description: "", value: .boolean(true)),
                ],
                stepOutputs: [],
                builtInMacroContext: defaultContext,
                expectation: .success("Debug: true")
            ),
            TestCase(
                description: "renders choice macro",
                input: "Type: {{ ___BUILD_TYPE___ }}",
                macros: [
                    ResolvedMacro(name: "___BUILD_TYPE___", description: "", value: .choice("release")),
                ],
                stepOutputs: [],
                builtInMacroContext: defaultContext,
                expectation: .success("Type: release")
            ),
            TestCase(
                description: "renders path macro as string",
                input: "Output: {{ ___OUTPUT_DIR___ }}",
                macros: [
                    ResolvedMacro(name: "___OUTPUT_DIR___", description: "", value: .path(URL(filePath: "/tmp/output"))),
                ],
                stepOutputs: [],
                builtInMacroContext: defaultContext,
                expectation: .success("Output: /tmp/output")
            ),

            // MARK: - Conditional blocks
            TestCase(
                description: "renders if block when true",
                input: "{% if ___USE_ASYNC___ %}async{% endif %}",
                macros: [
                    ResolvedMacro(name: "___USE_ASYNC___", description: "", value: .boolean(true)),
                ],
                stepOutputs: [],
                builtInMacroContext: defaultContext,
                expectation: .success("async")
            ),
            TestCase(
                description: "skips if block when false",
                input: "{% if ___USE_ASYNC___ %}async{% endif %}",
                macros: [
                    ResolvedMacro(name: "___USE_ASYNC___", description: "", value: .boolean(false)),
                ],
                stepOutputs: [],
                builtInMacroContext: defaultContext,
                expectation: .success("")
            ),
            TestCase(
                description: "renders if-else block",
                input: "{% if ___DEBUG___ %}debug{% else %}release{% endif %}",
                macros: [
                    ResolvedMacro(name: "___DEBUG___", description: "", value: .boolean(false)),
                ],
                stepOutputs: [],
                builtInMacroContext: defaultContext,
                expectation: .success("release")
            ),
            TestCase(
                description: "compares choice value",
                input: "{% if ___TYPE___ == \"app\" %}App{% else %}Library{% endif %}",
                macros: [
                    ResolvedMacro(name: "___TYPE___", description: "", value: .choice("app")),
                ],
                stepOutputs: [],
                builtInMacroContext: defaultContext,
                expectation: .success("App")
            ),

            // MARK: - Loop blocks
            TestCase(
                description: "iterates over array macro",
                input: "{% for m in ___MODULES___ %}import {{ m }}\n{% endfor %}",
                macros: [
                    ResolvedMacro(name: "___MODULES___", description: "", value: .array(["Foundation", "UIKit"])),
                ],
                stepOutputs: [],
                builtInMacroContext: defaultContext,
                expectation: .success("import Foundation\nimport UIKit\n")
            ),
            TestCase(
                description: "iterates over choices macro",
                input: "{% for p in ___PLATFORMS___ %}.{{ p }}{% if not forloop.last %}, {% endif %}{% endfor %}",
                macros: [
                    ResolvedMacro(name: "___PLATFORMS___", description: "", value: .choices(["iOS", "macOS"])),
                ],
                stepOutputs: [],
                builtInMacroContext: defaultContext,
                expectation: .success(".iOS, .macOS")
            ),
            TestCase(
                description: "handles empty array",
                input: "[{% for x in ___EMPTY___ %}{{ x }}{% endfor %}]",
                macros: [
                    ResolvedMacro(name: "___EMPTY___", description: "", value: .array([])),
                ],
                stepOutputs: [],
                builtInMacroContext: defaultContext,
                expectation: .success("[]")
            ),

            // MARK: - Step outputs
            TestCase(
                description: "accesses step output with dot notation",
                input: "v{{ pre_hatch.setup.outputs.version }}",
                macros: [],
                stepOutputs: [
                    TestOutput(phase: .preHatch, stepId: "setup", values: ["version": "1.0.0"]),
                ],
                builtInMacroContext: defaultContext,
                expectation: .success("v1.0.0")
            ),
            TestCase(
                description: "accesses post_hatch output",
                input: "URL: {{ post_hatch.deploy.outputs.url }}",
                macros: [],
                stepOutputs: [
                    TestOutput(phase: .postHatch, stepId: "deploy", values: ["url": "https://example.com"]),
                ],
                builtInMacroContext: defaultContext,
                expectation: .success("URL: https://example.com")
            ),

            // MARK: - Built-in macros (resolved before Stencil, using native egg syntax)
            TestCase(
                description: "resolves built-in DATE macro",
                input: "Created: ___DATE___",
                macros: [],
                stepOutputs: [],
                builtInMacroContext: BuiltInMacroContext(
                    outputDirectory: nil,
                    workingDirectory: URL(filePath: "/tmp"),
                    homeDirectory: URL(filePath: "/home"),
                    currentDate: Date(timeIntervalSince1970: 0),
                    environment: [:]
                ),
                expectation: .success("Created: " + BuiltInMacros.formatDate(Date(timeIntervalSince1970: 0), format: nil))
            ),

            // MARK: - Compound usage
            TestCase(
                description: "uses conditional inside loop",
                input: """
                    {% for m in ___MODULES___ %}{% if m == "UIKit" %}// iOS only
                    {% endif %}import {{ m }}
                    {% endfor %}
                    """,
                macros: [
                    ResolvedMacro(name: "___MODULES___", description: "", value: .array(["Foundation", "UIKit"])),
                ],
                stepOutputs: [],
                builtInMacroContext: defaultContext,
                expectation: .success("import Foundation\n// iOS only\nimport UIKit\n")
            ),
            TestCase(
                description: "combines macros and outputs",
                input: "{{ ___NAME___ }} v{{ pre_hatch.version.outputs.number }}",
                macros: [
                    ResolvedMacro(name: "___NAME___", description: "", value: .string("MyApp")),
                ],
                stepOutputs: [
                    TestOutput(phase: .preHatch, stepId: "version", values: ["number": "2.0.0"]),
                ],
                builtInMacroContext: defaultContext,
                expectation: .success("MyApp v2.0.0")
            ),

            // MARK: - Native syntax is NOT processed (passed through as-is)
            TestCase(
                description: "does not process native macro syntax",
                input: "Name: ___PROJECT_NAME___",
                macros: [
                    ResolvedMacro(name: "___PROJECT_NAME___", description: "", value: .string("MyApp")),
                ],
                stepOutputs: [],
                builtInMacroContext: defaultContext,
                expectation: .success("Name: ___PROJECT_NAME___")
            ),
            // Note: Native ${{ }} syntax is partially processed - the '$' remains but inner content is resolved
            // This documents current behavior; ideally these would pass through unchanged
            TestCase(
                description: "partially processes native step output syntax (current behavior)",
                input: "v${{ pre_hatch.setup.outputs.version }}",
                macros: [],
                stepOutputs: [
                    TestOutput(phase: .preHatch, stepId: "setup", values: ["version": "1.0.0"]),
                ],
                builtInMacroContext: defaultContext,
                expectation: .success("v$1.0.0")
            ),

            // MARK: - Error handling
            TestCase(
                description: "fails on syntax error",
                input: "{% if ___VAR___ %}unclosed",
                macros: [
                    ResolvedMacro(name: "___VAR___", description: "", value: .boolean(true)),
                ],
                stepOutputs: [],
                builtInMacroContext: defaultContext,
                expectation: .syntaxError
            ),
        ]
    }
}
