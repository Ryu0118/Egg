@testable import EggKit
import Foundation
import Testing

struct ConditionEvaluatorTests {
    @Test(arguments: TestCase.allCases)
    func evaluate(_ testCase: TestCase) async throws {
        let outputs = StepOutputsStorage()

        // Populate storage with test outputs
        for output in testCase.outputs {
            await outputs.store(phase: output.phase, stepId: output.stepId, outputs: output.values)
        }

        let evaluator = ConditionEvaluator(macros: testCase.macros, outputs: outputs)

        switch testCase.expectation {
        case let .success(expectedResult):
            let result = try await evaluator.evaluate(testCase.condition)
            #expect(result == expectedResult)

        case let .failure(expectedError):
            let error = await #expect(throws: LifecycleStepError.self) {
                try await evaluator.evaluate(testCase.condition)
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
        let condition: String
        let macros: [ResolvedMacro]
        let outputs: [TestOutput]
        let expectation: Expectation

        var testDescription: String { description }

        enum Expectation {
            case success(expectedResult: Bool)
            case failure(expectedError: LifecycleStepError)
        }

        static let allCases: [TestCase] = [
            // Basic boolean conditions
            TestCase(
                description: "evaluates simple true condition",
                condition: "true",
                macros: [],
                outputs: [],
                expectation: .success(expectedResult: true)
            ),
            TestCase(
                description: "evaluates simple false condition",
                condition: "false",
                macros: [],
                outputs: [],
                expectation: .success(expectedResult: false)
            ),

            // Boolean macro evaluation
            TestCase(
                description: "evaluates boolean macro true comparison",
                condition: "___DEBUG___ === true",
                macros: [
                    ResolvedMacro(name: "___DEBUG___", description: "Debug Mode", value: .boolean(true)),
                ],
                outputs: [],
                expectation: .success(expectedResult: true)
            ),
            TestCase(
                description: "evaluates boolean macro false comparison",
                condition: "___DEBUG___ === false",
                macros: [
                    ResolvedMacro(name: "___DEBUG___", description: "Debug Mode", value: .boolean(false)),
                ],
                outputs: [],
                expectation: .success(expectedResult: true)
            ),
            TestCase(
                description: "evaluates boolean macro with !== operator",
                condition: "___DEBUG___ !== false",
                macros: [
                    ResolvedMacro(name: "___DEBUG___", description: "Debug Mode", value: .boolean(true)),
                ],
                outputs: [],
                expectation: .success(expectedResult: true)
            ),

            // String macro evaluation
            TestCase(
                description: "evaluates string macro comparison",
                condition: "___NAME___ === \"MyApp\"",
                macros: [
                    ResolvedMacro(name: "___NAME___", description: "Name", value: .string("MyApp")),
                ],
                outputs: [],
                expectation: .success(expectedResult: true)
            ),
            TestCase(
                description: "evaluates string macro with !== operator",
                condition: "___NAME___ !== \"OtherApp\"",
                macros: [
                    ResolvedMacro(name: "___NAME___", description: "Name", value: .string("MyApp")),
                ],
                outputs: [],
                expectation: .success(expectedResult: true)
            ),

            // Choice macro evaluation
            TestCase(
                description: "evaluates choice macro comparison",
                condition: "___BUILD_TYPE___ === \"release\"",
                macros: [
                    ResolvedMacro(name: "___BUILD_TYPE___", description: "Build Type", value: .choice("release")),
                ],
                outputs: [],
                expectation: .success(expectedResult: true)
            ),

            // Path macro evaluation
            TestCase(
                description: "evaluates path macro comparison",
                condition: "___OUTPUT_DIR___ === \"/tmp/test\"",
                macros: [
                    ResolvedMacro(name: "___OUTPUT_DIR___", description: "Output Directory", value: .path(URL(filePath: "/tmp/test"))),
                ],
                outputs: [],
                expectation: .success(expectedResult: true)
            ),

            // Array macro with includes()
            TestCase(
                description: "evaluates array includes with matching element",
                condition: "___PLATFORMS___.includes(\"iOS\")",
                macros: [
                    ResolvedMacro(name: "___PLATFORMS___", description: "Platforms", value: .array(["iOS", "macOS"])),
                ],
                outputs: [],
                expectation: .success(expectedResult: true)
            ),
            TestCase(
                description: "evaluates array includes with non-matching element",
                condition: "___PLATFORMS___.includes(\"watchOS\")",
                macros: [
                    ResolvedMacro(name: "___PLATFORMS___", description: "Platforms", value: .array(["iOS", "macOS"])),
                ],
                outputs: [],
                expectation: .success(expectedResult: false)
            ),
            TestCase(
                description: "evaluates array includes with empty array",
                condition: "___PLATFORMS___.includes(\"iOS\")",
                macros: [
                    ResolvedMacro(name: "___PLATFORMS___", description: "Platforms", value: .array([])),
                ],
                outputs: [],
                expectation: .success(expectedResult: false)
            ),

            // Step output evaluation (user quotes in condition)
            TestCase(
                description: "evaluates step output string comparison",
                condition: "\"${{ pre_hatch.setup.outputs.status }}\" === \"success\"",
                macros: [],
                outputs: [
                    TestOutput(phase: .preHatch, stepId: "setup", values: ["status": "success"]),
                ],
                expectation: .success(expectedResult: true)
            ),
            TestCase(
                description: "evaluates step output with !== operator",
                condition: "\"${{ pre_hatch.setup.outputs.status }}\" !== \"failed\"",
                macros: [],
                outputs: [
                    TestOutput(phase: .preHatch, stepId: "setup", values: ["status": "success"]),
                ],
                expectation: .success(expectedResult: true)
            ),
            TestCase(
                description: "evaluates post_hatch output string",
                condition: "\"${{ post_hatch.deploy.outputs.url }}\" === \"https://example.com\"",
                macros: [],
                outputs: [
                    TestOutput(phase: .postHatch, stepId: "deploy", values: ["url": "https://example.com"]),
                ],
                expectation: .success(expectedResult: true)
            ),

            // Complex expressions with && operator
            TestCase(
                description: "evaluates AND operator with both true",
                condition: "___DEBUG___ && ___PLATFORMS___.includes(\"iOS\")",
                macros: [
                    ResolvedMacro(name: "___DEBUG___", description: "Debug", value: .boolean(true)),
                    ResolvedMacro(name: "___PLATFORMS___", description: "Platforms", value: .array(["iOS"])),
                ],
                outputs: [],
                expectation: .success(expectedResult: true)
            ),
            TestCase(
                description: "evaluates AND operator with first false",
                condition: "___DEBUG___ && ___PLATFORMS___.includes(\"iOS\")",
                macros: [
                    ResolvedMacro(name: "___DEBUG___", description: "Debug", value: .boolean(false)),
                    ResolvedMacro(name: "___PLATFORMS___", description: "Platforms", value: .array(["iOS"])),
                ],
                outputs: [],
                expectation: .success(expectedResult: false)
            ),

            // Complex expressions with || operator
            TestCase(
                description: "evaluates OR operator with first true",
                condition: "___DEBUG___ || ___SKIP___",
                macros: [
                    ResolvedMacro(name: "___DEBUG___", description: "Debug", value: .boolean(true)),
                    ResolvedMacro(name: "___SKIP___", description: "Skip", value: .boolean(false)),
                ],
                outputs: [],
                expectation: .success(expectedResult: true)
            ),
            TestCase(
                description: "evaluates OR operator with both false",
                condition: "___DEBUG___ || ___SKIP___",
                macros: [
                    ResolvedMacro(name: "___DEBUG___", description: "Debug", value: .boolean(false)),
                    ResolvedMacro(name: "___SKIP___", description: "Skip", value: .boolean(false)),
                ],
                outputs: [],
                expectation: .success(expectedResult: false)
            ),

            // Complex expressions with parentheses
            TestCase(
                description: "evaluates complex expression with parentheses - true result",
                condition: "(___DEBUG___ && ___PLATFORMS___.includes(\"iOS\")) || ___SKIP___",
                macros: [
                    ResolvedMacro(name: "___DEBUG___", description: "Debug", value: .boolean(true)),
                    ResolvedMacro(name: "___PLATFORMS___", description: "Platforms", value: .array(["iOS"])),
                    ResolvedMacro(name: "___SKIP___", description: "Skip", value: .boolean(false)),
                ],
                outputs: [],
                expectation: .success(expectedResult: true)
            ),
            TestCase(
                description: "evaluates complex expression with parentheses - false result",
                condition: "(___DEBUG___ && ___PLATFORMS___.includes(\"watchOS\")) || ___SKIP___",
                macros: [
                    ResolvedMacro(name: "___DEBUG___", description: "Debug", value: .boolean(true)),
                    ResolvedMacro(name: "___PLATFORMS___", description: "Platforms", value: .array(["iOS"])),
                    ResolvedMacro(name: "___SKIP___", description: "Skip", value: .boolean(false)),
                ],
                outputs: [],
                expectation: .success(expectedResult: false)
            ),

            // Mixed macro and output references
            TestCase(
                description: "evaluates mixed macro and output - true result",
                condition: "___DEBUG___ && \"${{ pre_hatch.setup.outputs.status }}\" === \"ready\"",
                macros: [
                    ResolvedMacro(name: "___DEBUG___", description: "Debug", value: .boolean(true)),
                ],
                outputs: [
                    TestOutput(phase: .preHatch, stepId: "setup", values: ["status": "ready"]),
                ],
                expectation: .success(expectedResult: true)
            ),
            TestCase(
                description: "evaluates mixed macro and output - false result",
                condition: "___DEBUG___ && \"${{ pre_hatch.setup.outputs.status }}\" === \"failed\"",
                macros: [
                    ResolvedMacro(name: "___DEBUG___", description: "Debug", value: .boolean(true)),
                ],
                outputs: [
                    TestOutput(phase: .preHatch, stepId: "setup", values: ["status": "ready"]),
                ],
                expectation: .success(expectedResult: false)
            ),

            // String escaping tests
            TestCase(
                description: "handles strings with quotes",
                condition: "___MESSAGE___ === \"Hello \\\"World\\\"\"",
                macros: [
                    ResolvedMacro(name: "___MESSAGE___", description: "Message", value: .string("Hello \"World\"")),
                ],
                outputs: [],
                expectation: .success(expectedResult: true)
            ),
            TestCase(
                description: "handles strings with backslashes",
                condition: "___PATH___ === \"C:\\\\\\\\Users\\\\\\\\test\"",
                macros: [
                    ResolvedMacro(name: "___PATH___", description: "Path", value: .string("C:\\\\Users\\\\test")),
                ],
                outputs: [],
                expectation: .success(expectedResult: true)
            ),

            // Error cases - undefined output reference
            TestCase(
                description: "throws error for undefined output key",
                condition: "\"${{ pre_hatch.setup.outputs.unknown }}\" === \"true\"",
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
                description: "throws error for undefined step ID",
                condition: "\"${{ pre_hatch.unknown.outputs.version }}\" === \"1.0.0\"",
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
                description: "throws error for undefined phase",
                condition: "\"${{ invalid_phase.setup.outputs.version }}\" === \"1.0.0\"",
                macros: [],
                outputs: [],
                expectation: .failure(expectedError: .undefinedOutputReference(
                    phase: .preHatch, // Fallback to .preHatch for invalid phase
                    stepId: "setup",
                    key: "version"
                ))
            ),

            // Error cases - invalid JavaScript syntax
            TestCase(
                description: "throws error for invalid syntax",
                condition: "!@#$%^&*()",
                macros: [],
                outputs: [],
                expectation: .failure(expectedError: .conditionEvaluationError(
                    condition: "!@#$%^&*()",
                    reason: "JavaScript evaluation failed or returned null/undefined"
                ))
            ),
            TestCase(
                description: "throws error for non-boolean result",
                condition: "\"hello\"",
                macros: [],
                outputs: [],
                expectation: .failure(expectedError: .conditionEvaluationError(
                    condition: "\"hello\"",
                    reason: "Condition must evaluate to a boolean, got: hello"
                ))
            ),

            // Edge cases
            TestCase(
                description: "handles whitespace in output reference",
                condition: "\"${{  pre_hatch.setup.outputs.version  }}\" === \"1.0.0\"",
                macros: [],
                outputs: [
                    TestOutput(phase: .preHatch, stepId: "setup", values: ["version": "1.0.0"]),
                ],
                expectation: .success(expectedResult: true)
            ),
            TestCase(
                description: "handles step ID with hyphens",
                condition: "\"${{ pre_hatch.my-step-1.outputs.result }}\" === \"ok\"",
                macros: [],
                outputs: [
                    TestOutput(phase: .preHatch, stepId: "my-step-1", values: ["result": "ok"]),
                ],
                expectation: .success(expectedResult: true)
            ),
            TestCase(
                description: "handles output key with hyphens",
                condition: "\"${{ pre_hatch.setup.outputs.src-dir }}\" === \"/tmp/src\"",
                macros: [],
                outputs: [
                    TestOutput(phase: .preHatch, stepId: "setup", values: ["src-dir": "/tmp/src"]),
                ],
                expectation: .success(expectedResult: true)
            ),
            TestCase(
                description: "handles output key with dots",
                condition: "\"${{ pre_hatch.setup.outputs.app.name }}\" === \"MyApp\"",
                macros: [],
                outputs: [
                    TestOutput(phase: .preHatch, stepId: "setup", values: ["app.name": "MyApp"]),
                ],
                expectation: .success(expectedResult: true)
            ),

            // Cross-phase access
            TestCase(
                description: "supports cross-phase output access",
                condition: "\"${{ post_hatch.deploy.outputs.url }}\" === \"https://example.com\"",
                macros: [],
                outputs: [
                    TestOutput(phase: .preHatch, stepId: "setup", values: ["version": "1.0.0"]),
                    TestOutput(phase: .postHatch, stepId: "deploy", values: ["url": "https://example.com"]),
                ],
                expectation: .success(expectedResult: true)
            ),

            // Multiple macros
            TestCase(
                description: "handles multiple macros in expression",
                condition: "___NAME___ === \"MyApp\" && ___DEBUG___ === true",
                macros: [
                    ResolvedMacro(name: "___NAME___", description: "Name", value: .string("MyApp")),
                    ResolvedMacro(name: "___DEBUG___", description: "Debug", value: .boolean(true)),
                ],
                outputs: [],
                expectation: .success(expectedResult: true)
            ),

            // Multiple outputs
            TestCase(
                description: "handles multiple output references",
                condition: "\"${{ pre_hatch.setup.outputs.name }}\" === \"MyApp\" && \"${{ pre_hatch.setup.outputs.version }}\" === \"1.0.0\"",
                macros: [],
                outputs: [
                    TestOutput(phase: .preHatch, stepId: "setup", values: ["name": "MyApp", "version": "1.0.0"]),
                ],
                expectation: .success(expectedResult: true)
            ),
        ]
    }
}
