@testable import EggKit
import Foundation
import Path
import ProcessRunning
import Testing

struct LifecycleStepRunnerTests {
    @Test(arguments: TestCase.allCases)
    func executePhase(_ testCase: TestCase) async throws {
        let processRunner = ProcessRunner()
        let workingDirectory = try AbsolutePath(validating: NSTemporaryDirectory())

        let runner = LifecycleStepRunner(
            processRunner: processRunner,
            workingDirectory: workingDirectory
        )

        let initialOutputs = StepOutputsStorage()

        // Populate initial outputs if provided
        for output in testCase.initialOutputs {
            await initialOutputs.store(phase: output.phase, stepId: output.stepId, outputs: output.values)
        }

        switch testCase.expectation {
        case let .success(expectedOutputs):
            let outputs = try await runner.execute(
                testCase.phase,
                steps: testCase.steps,
                substituting: testCase.macros,
                merging: initialOutputs
            )

            // Verify expected outputs
            for expected in expectedOutputs {
                for (key, expectedValue) in expected.values {
                    let actualValue = await outputs.get(phase: expected.phase, stepId: expected.stepId, key: key)
                    #expect(actualValue == expectedValue, "Expected '\(expectedValue)' for \(expected.phase.rawValue).\(expected.stepId).\(key), got '\(actualValue ?? "nil")'")
                }
            }

        case let .failure(expectedError):
            let error = await #expect(throws: LifecycleStepError.self) {
                try await runner.execute(
                    testCase.phase,
                    steps: testCase.steps,
                    substituting: testCase.macros,
                    merging: initialOutputs
                )
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
        let phase: LifecyclePhase
        let steps: [Config.LifecycleStep]
        let macros: [ResolvedMacro]
        let initialOutputs: [TestOutput]
        let expectation: Expectation

        var testDescription: String { description }

        enum Expectation {
            case success(expectedOutputs: [TestOutput])
            case failure(expectedError: LifecycleStepError)
        }

        static let allCases: [TestCase] = [
            // Basic execution - single step with output
            TestCase(
                description: "executes single step and captures output",
                phase: .preHatch,
                steps: [
                    Config.LifecycleStep(
                        id: "setup",
                        if: nil,
                        run: "echo \"version=1.0.0\""
                    ),
                ],
                macros: [],
                initialOutputs: [],
                expectation: .success(expectedOutputs: [
                    TestOutput(phase: .preHatch, stepId: "setup", values: ["version": "1.0.0"]),
                ])
            ),

            // Multiple outputs from single step
            TestCase(
                description: "captures multiple outputs from single step",
                phase: .preHatch,
                steps: [
                    Config.LifecycleStep(
                        id: "setup",
                        if: nil,
                        run: """
                        echo "version=1.0.0"
                        echo "name=MyApp"
                        echo "platform=iOS"
                        """
                    ),
                ],
                macros: [],
                initialOutputs: [],
                expectation: .success(expectedOutputs: [
                    TestOutput(phase: .preHatch, stepId: "setup", values: [
                        "version": "1.0.0",
                        "name": "MyApp",
                        "platform": "iOS",
                    ]),
                ])
            ),

            // Multiple steps with sequential dependencies
            TestCase(
                description: "executes multiple steps with output references",
                phase: .preHatch,
                steps: [
                    Config.LifecycleStep(
                        id: "setup",
                        if: nil,
                        run: "echo \"version=1.0.0\""
                    ),
                    Config.LifecycleStep(
                        id: "build",
                        if: nil,
                        run: "echo \"build-version=${{ pre_hatch.setup.outputs.version }}\""
                    ),
                ],
                macros: [],
                initialOutputs: [],
                expectation: .success(expectedOutputs: [
                    TestOutput(phase: .preHatch, stepId: "setup", values: ["version": "1.0.0"]),
                    TestOutput(phase: .preHatch, stepId: "build", values: ["build-version": "1.0.0"]),
                ])
            ),

            // Macro substitution
            TestCase(
                description: "substitutes macros in step commands",
                phase: .preHatch,
                steps: [
                    Config.LifecycleStep(
                        id: "echo-name",
                        if: nil,
                        run: "echo \"project-name=___PROJECT_NAME___\""
                    ),
                ],
                macros: [
                    ResolvedMacro(name: "___PROJECT_NAME___", description: "Project Name", value: .string("MyApp")),
                ],
                initialOutputs: [],
                expectation: .success(expectedOutputs: [
                    TestOutput(phase: .preHatch, stepId: "echo-name", values: ["project-name": "MyApp"]),
                ])
            ),

            // Conditional execution - condition true
            TestCase(
                description: "executes step when condition is true",
                phase: .preHatch,
                steps: [
                    Config.LifecycleStep(
                        id: "conditional",
                        if: "___DEBUG___ === true",
                        run: "echo \"executed=yes\""
                    ),
                ],
                macros: [
                    ResolvedMacro(name: "___DEBUG___", description: "Debug", value: .boolean(true)),
                ],
                initialOutputs: [],
                expectation: .success(expectedOutputs: [
                    TestOutput(phase: .preHatch, stepId: "conditional", values: ["executed": "yes"]),
                ])
            ),

            // Conditional execution - condition false (step skipped)
            TestCase(
                description: "skips step when condition is false",
                phase: .preHatch,
                steps: [
                    Config.LifecycleStep(
                        id: "skipped",
                        if: "___DEBUG___ === true",
                        run: "echo \"should-not-execute=yes\""
                    ),
                ],
                macros: [
                    ResolvedMacro(name: "___DEBUG___", description: "Debug", value: .boolean(false)),
                ],
                initialOutputs: [],
                expectation: .success(expectedOutputs: [])
            ),

            // Step without ID (no output captured)
            TestCase(
                description: "executes step without ID and does not capture output",
                phase: .preHatch,
                steps: [
                    Config.LifecycleStep(
                        id: nil,
                        if: nil,
                        run: "echo \"version=1.0.0\""
                    ),
                ],
                macros: [],
                initialOutputs: [],
                expectation: .success(expectedOutputs: [])
            ),

            // Cross-phase output reference
            TestCase(
                description: "accesses outputs from previous phase",
                phase: .postHatch,
                steps: [
                    Config.LifecycleStep(
                        id: "deploy",
                        if: nil,
                        run: "echo \"deployed-version=${{ pre_hatch.setup.outputs.version }}\""
                    ),
                ],
                macros: [],
                initialOutputs: [
                    TestOutput(phase: .preHatch, stepId: "setup", values: ["version": "1.0.0"]),
                ],
                expectation: .success(expectedOutputs: [
                    TestOutput(phase: .postHatch, stepId: "deploy", values: ["deployed-version": "1.0.0"]),
                ])
            ),

            // Conditional with step output
            TestCase(
                description: "evaluates condition with step output reference",
                phase: .preHatch,
                steps: [
                    Config.LifecycleStep(
                        id: "setup",
                        if: nil,
                        run: "echo \"ready=true\""
                    ),
                    Config.LifecycleStep(
                        id: "conditional",
                        if: "\"${{ pre_hatch.setup.outputs.ready }}\" === \"true\"",
                        run: "echo \"executed=yes\""
                    ),
                ],
                macros: [],
                initialOutputs: [],
                expectation: .success(expectedOutputs: [
                    TestOutput(phase: .preHatch, stepId: "setup", values: ["ready": "true"]),
                    TestOutput(phase: .preHatch, stepId: "conditional", values: ["executed": "yes"]),
                ])
            ),

            // Complex condition with macro and output
            TestCase(
                description: "evaluates complex condition with macro and output",
                phase: .preHatch,
                steps: [
                    Config.LifecycleStep(
                        id: "setup",
                        if: nil,
                        run: "echo \"status=ready\""
                    ),
                    Config.LifecycleStep(
                        id: "build",
                        if: "___DEBUG___ && \"${{ pre_hatch.setup.outputs.status }}\" === \"ready\"",
                        run: "echo \"built=yes\""
                    ),
                ],
                macros: [
                    ResolvedMacro(name: "___DEBUG___", description: "Debug", value: .boolean(true)),
                ],
                initialOutputs: [],
                expectation: .success(expectedOutputs: [
                    TestOutput(phase: .preHatch, stepId: "setup", values: ["status": "ready"]),
                    TestOutput(phase: .preHatch, stepId: "build", values: ["built": "yes"]),
                ])
            ),

            // Array macro with includes()
            TestCase(
                description: "evaluates array macro with includes() in condition",
                phase: .preHatch,
                steps: [
                    Config.LifecycleStep(
                        id: "ios-step",
                        if: "___PLATFORMS___.includes(\"iOS\")",
                        run: "echo \"platform=iOS\""
                    ),
                ],
                macros: [
                    ResolvedMacro(name: "___PLATFORMS___", description: "Platforms", value: .array(["iOS", "macOS"])),
                ],
                initialOutputs: [],
                expectation: .success(expectedOutputs: [
                    TestOutput(phase: .preHatch, stepId: "ios-step", values: ["platform": "iOS"]),
                ])
            ),

            // Error case - undefined output reference
            TestCase(
                description: "throws error for undefined output reference",
                phase: .preHatch,
                steps: [
                    Config.LifecycleStep(
                        id: "fail",
                        if: nil,
                        run: "echo \"value=${{ pre_hatch.unknown.outputs.key }}\""
                    ),
                ],
                macros: [],
                initialOutputs: [],
                expectation: .failure(expectedError: .undefinedOutputReference(
                    phase: .preHatch,
                    stepId: "unknown",
                    key: "key"
                ))
            ),

            // Error case - invalid condition
            TestCase(
                description: "throws error for invalid condition syntax",
                phase: .preHatch,
                steps: [
                    Config.LifecycleStep(
                        id: "fail",
                        if: "!@#$%^&*()",
                        run: "echo \"should-not-execute=yes\""
                    ),
                ],
                macros: [],
                initialOutputs: [],
                expectation: .failure(expectedError: .conditionEvaluationError(
                    condition: "!@#$%^&*()",
                    reason: "JavaScript evaluation failed or returned null/undefined"
                ))
            ),

            // Multiple steps with some skipped
            TestCase(
                description: "executes selective steps based on conditions",
                phase: .preHatch,
                steps: [
                    Config.LifecycleStep(
                        id: "always",
                        if: nil,
                        run: "echo \"always=yes\""
                    ),
                    Config.LifecycleStep(
                        id: "debug-only",
                        if: "___DEBUG___ === true",
                        run: "echo \"debug=yes\""
                    ),
                    Config.LifecycleStep(
                        id: "release-only",
                        if: "___DEBUG___ === false",
                        run: "echo \"release=yes\""
                    ),
                ],
                macros: [
                    ResolvedMacro(name: "___DEBUG___", description: "Debug", value: .boolean(true)),
                ],
                initialOutputs: [],
                expectation: .success(expectedOutputs: [
                    TestOutput(phase: .preHatch, stepId: "always", values: ["always": "yes"]),
                    TestOutput(phase: .preHatch, stepId: "debug-only", values: ["debug": "yes"]),
                    // release-only is skipped
                ])
            ),
        ]
    }
}
