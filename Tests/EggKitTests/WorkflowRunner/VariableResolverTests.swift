@testable import EggKit
import Foundation
import Testing

struct VariableResolverTests {
    @Test(arguments: TestCase.allCases)
    func resolve(_ testCase: TestCase) async throws {
        let outputs = StepOutputsStorage()

        // Populate storage with test outputs
        for output in testCase.outputs {
            await outputs.store(phase: output.phase, stepId: output.stepId, outputs: output.values)
        }

        let resolver = VariableResolver(macros: testCase.macros, outputs: outputs)

        switch testCase.expectation {
        case let .success(expectedResult):
            let result = try await resolver.resolve(testCase.input)
            #expect(result == expectedResult)

        case let .failure(expectedError):
            let error = await #expect(throws: LifecycleStepError.self) {
                try await resolver.resolve(testCase.input)
            }

            guard let error else {
                Issue.record("Expected LifecycleStepError but got different error")
                return
            }

            #expect(error == expectedError)
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
        let outputs: [TestOutput]
        let expectation: Expectation

        var testDescription: String { description }

        enum Expectation {
            case success(expectedResult: String)
            case failure(expectedError: LifecycleStepError)
        }

        static let allCases: [TestCase] = [
            TestCase(
                description: "resolves string macro",
                input: "App name is ___PROJECT_NAME___",
                macros: [
                    ResolvedMacro(name: "___PROJECT_NAME___", description: "Project Name", value: .string("MyApp")),
                ],
                outputs: [],
                expectation: .success(expectedResult: "App name is MyApp")
            ),
            TestCase(
                description: "resolves boolean macro true",
                input: "Debug: ___DEBUG___",
                macros: [
                    ResolvedMacro(name: "___DEBUG___", description: "Debug Mode", value: .boolean(true)),
                ],
                outputs: [],
                expectation: .success(expectedResult: "Debug: true")
            ),
            TestCase(
                description: "resolves boolean macro false",
                input: "Debug: ___DEBUG___",
                macros: [
                    ResolvedMacro(name: "___DEBUG___", description: "Debug Mode", value: .boolean(false)),
                ],
                outputs: [],
                expectation: .success(expectedResult: "Debug: false")
            ),
            TestCase(
                description: "resolves choice macro",
                input: "Build: ___BUILD_TYPE___",
                macros: [
                    ResolvedMacro(name: "___BUILD_TYPE___", description: "Build Type", value: .choice("release")),
                ],
                outputs: [],
                expectation: .success(expectedResult: "Build: release")
            ),
            TestCase(
                description: "resolves array macro with comma-separated values",
                input: "Platforms: ___PLATFORMS___",
                macros: [
                    ResolvedMacro(name: "___PLATFORMS___", description: "Platforms", value: .array(["iOS", "macOS", "watchOS"])),
                ],
                outputs: [],
                expectation: .success(expectedResult: "Platforms: iOS,macOS,watchOS")
            ),
            TestCase(
                description: "resolves path macro",
                input: "Output: ___OUTPUT_DIR___",
                macros: [
                    ResolvedMacro(name: "___OUTPUT_DIR___", description: "Output Directory", value: .path(URL(filePath: "/tmp/test"))),
                ],
                outputs: [],
                expectation: .success(expectedResult: "Output: /tmp/test")
            ),
            TestCase(
                description: "resolves multiple macros in single string",
                input: "___NAME___ v___VERSION___ (debug: ___DEBUG___)",
                macros: [
                    ResolvedMacro(name: "___NAME___", description: "Name", value: .string("MyApp")),
                    ResolvedMacro(name: "___VERSION___", description: "Version", value: .string("1.0.0")),
                    ResolvedMacro(name: "___DEBUG___", description: "Debug", value: .boolean(true)),
                ],
                outputs: [],
                expectation: .success(expectedResult: "MyApp v1.0.0 (debug: true)")
            ),
            TestCase(
                description: "does not replace when macro pattern doesn't match exactly",
                input: "__NAME__ and ____NAME____",
                macros: [
                    ResolvedMacro(name: "___NAME___", description: "Name", value: .string("MyApp")),
                ],
                outputs: [],
                expectation: .success(expectedResult: "__NAME__ and _MyApp_")
            ),
            TestCase(
                description: "macro resolution is case-sensitive",
                input: "___name___ and ___Name___ should not be replaced",
                macros: [
                    ResolvedMacro(name: "___NAME___", description: "Name", value: .string("MyApp")),
                ],
                outputs: [],
                expectation: .success(expectedResult: "___name___ and ___Name___ should not be replaced")
            ),
            TestCase(
                description: "resolves single step output reference",
                input: "Version: ${{ pre_hatch.setup.outputs.version }}",
                macros: [],
                outputs: [
                    TestOutput(phase: .preHatch, stepId: "setup", values: ["version": "1.0.0"]),
                ],
                expectation: .success(expectedResult: "Version: 1.0.0")
            ),
            TestCase(
                description: "resolves multiple step output references",
                input: "${{ pre_hatch.setup.outputs.name }} v${{ pre_hatch.setup.outputs.version }}",
                macros: [],
                outputs: [
                    TestOutput(phase: .preHatch, stepId: "setup", values: ["version": "1.0.0", "name": "MyApp"]),
                ],
                expectation: .success(expectedResult: "MyApp v1.0.0")
            ),
            TestCase(
                description: "resolves step ID with hyphens",
                input: "Result: ${{ pre_hatch.my-step-1.outputs.result }}",
                macros: [],
                outputs: [
                    TestOutput(phase: .preHatch, stepId: "my-step-1", values: ["result": "ok"]),
                ],
                expectation: .success(expectedResult: "Result: ok")
            ),
            TestCase(
                description: "resolves output key with hyphens",
                input: "Source: ${{ pre_hatch.setup.outputs.src-dir }}",
                macros: [],
                outputs: [
                    TestOutput(phase: .preHatch, stepId: "setup", values: ["src-dir": "/tmp/src"]),
                ],
                expectation: .success(expectedResult: "Source: /tmp/src")
            ),
            TestCase(
                description: "resolves output key with dots",
                input: "App: ${{ pre_hatch.setup.outputs.app.name }}",
                macros: [],
                outputs: [
                    TestOutput(phase: .preHatch, stepId: "setup", values: ["app.name": "MyApp"]),
                ],
                expectation: .success(expectedResult: "App: MyApp")
            ),
            TestCase(
                description: "handles whitespace in step output reference",
                input: "Version: ${{  pre_hatch.setup.outputs.version  }}",
                macros: [],
                outputs: [
                    TestOutput(phase: .preHatch, stepId: "setup", values: ["version": "1.0.0"]),
                ],
                expectation: .success(expectedResult: "Version: 1.0.0")
            ),
            TestCase(
                description: "throws when output key does not exist",
                input: "Value: ${{ pre_hatch.setup.outputs.unknown }}",
                macros: [],
                outputs: [
                    TestOutput(phase: .preHatch, stepId: "setup", values: ["version": "1.0.0"]),
                ],
                expectation: .failure(expectedError: .undefinedOutputReference(
                    phase: .preHatch,
                    stepId: "setup",
                    key: "unknown"
                ))
            ),
            TestCase(
                description: "throws when step ID does not exist",
                input: "Value: ${{ pre_hatch.unknown.outputs.version }}",
                macros: [],
                outputs: [
                    TestOutput(phase: .preHatch, stepId: "setup", values: ["version": "1.0.0"]),
                ],
                expectation: .failure(expectedError: .undefinedOutputReference(
                    phase: .preHatch,
                    stepId: "unknown",
                    key: "version"
                ))
            ),
            TestCase(
                description: "throws when phase does not exist",
                input: "Value: ${{ invalid_phase.setup.outputs.version }}",
                macros: [],
                outputs: [],
                expectation: .failure(expectedError: .undefinedOutputReference(
                    phase: .preHatch, // Fallback to .preHatch for invalid phase
                    stepId: "setup",
                    key: "version"
                ))
            ),
            TestCase(
                description: "supports cross-phase output access",
                input: "Deployed to ${{ post_hatch.deploy.outputs.url }}",
                macros: [],
                outputs: [
                    TestOutput(phase: .preHatch, stepId: "setup", values: ["version": "1.0.0"]),
                    TestOutput(phase: .postHatch, stepId: "deploy", values: ["url": "https://example.com"]),
                ],
                expectation: .success(expectedResult: "Deployed to https://example.com")
            ),
            TestCase(
                description: "post_hatch can reference pre_hatch outputs",
                input: "Built version ${{ pre_hatch.setup.outputs.version }}",
                macros: [],
                outputs: [
                    TestOutput(phase: .preHatch, stepId: "setup", values: ["version": "1.0.0"]),
                ],
                expectation: .success(expectedResult: "Built version 1.0.0")
            ),
            TestCase(
                description: "resolves macros and step outputs together",
                input: "___PROJECT_NAME___ v${{ pre_hatch.setup.outputs.version }}",
                macros: [
                    ResolvedMacro(name: "___PROJECT_NAME___", description: "Project Name", value: .string("MyApp")),
                ],
                outputs: [
                    TestOutput(phase: .preHatch, stepId: "setup", values: ["version": "1.0.0"]),
                ],
                expectation: .success(expectedResult: "MyApp v1.0.0")
            ),
            TestCase(
                description: "resolves multiple macros and multiple outputs",
                input: "___NAME___ v${{ pre_hatch.setup.outputs.version }} build ${{ pre_hatch.setup.outputs.build }} (debug: ___DEBUG___)",
                macros: [
                    ResolvedMacro(name: "___NAME___", description: "Name", value: .string("MyApp")),
                    ResolvedMacro(name: "___DEBUG___", description: "Debug", value: .boolean(true)),
                ],
                outputs: [
                    TestOutput(phase: .preHatch, stepId: "setup", values: ["version": "1.0.0", "build": "42"]),
                ],
                expectation: .success(expectedResult: "MyApp v1.0.0 build 42 (debug: true)")
            ),
            TestCase(
                description: "two-pass order prevents ambiguity",
                input: "___TEMPLATE___",
                macros: [
                    ResolvedMacro(name: "___TEMPLATE___", description: "Template", value: .string("Version: ${{ pre_hatch.setup.outputs.version }}")),
                ],
                outputs: [
                    TestOutput(phase: .preHatch, stepId: "setup", values: ["version": "1.0.0"]),
                ],
                expectation: .success(expectedResult: "Version: 1.0.0")
            ),
            TestCase(
                description: "returns empty string unchanged",
                input: "",
                macros: [],
                outputs: [],
                expectation: .success(expectedResult: "")
            ),
            TestCase(
                description: "returns string with no variables unchanged",
                input: "This is a plain string with no variables",
                macros: [],
                outputs: [],
                expectation: .success(expectedResult: "This is a plain string with no variables")
            ),
            TestCase(
                description: "handles output value containing special characters",
                input: "URL: ${{ pre_hatch.setup.outputs.url }}, PATH: ${{ pre_hatch.setup.outputs.path }}",
                macros: [],
                outputs: [
                    TestOutput(phase: .preHatch, stepId: "setup", values: [
                        "url": "https://example.com/path?query=value&foo=bar",
                        "path": "/usr/local/bin:/usr/bin:/bin",
                    ]),
                ],
                expectation: .success(expectedResult: "URL: https://example.com/path?query=value&foo=bar, PATH: /usr/local/bin:/usr/bin:/bin")
            ),
            TestCase(
                description: "handles output value containing equals sign",
                input: "Equation: ${{ pre_hatch.setup.outputs.equation }}",
                macros: [],
                outputs: [
                    TestOutput(phase: .preHatch, stepId: "setup", values: ["equation": "x=y+z"]),
                ],
                expectation: .success(expectedResult: "Equation: x=y+z")
            ),
            TestCase(
                description: "handles unicode characters in values",
                input: "___GREETING___ ${{ pre_hatch.setup.outputs.emoji }}",
                macros: [
                    ResolvedMacro(name: "___GREETING___", description: "Greeting", value: .string("こんにちは")),
                ],
                outputs: [
                    TestOutput(phase: .preHatch, stepId: "setup", values: ["emoji": "🚀"]),
                ],
                expectation: .success(expectedResult: "こんにちは 🚀")
            ),
            TestCase(
                description: "handles empty output value",
                input: "Value: [${{ pre_hatch.setup.outputs.empty }}]",
                macros: [],
                outputs: [
                    TestOutput(phase: .preHatch, stepId: "setup", values: ["empty": ""]),
                ],
                expectation: .success(expectedResult: "Value: []")
            ),
        ]
    }
}
