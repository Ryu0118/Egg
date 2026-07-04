@testable import EggKit
import Foundation
import Testing

struct StepOutputsStorageTests {
    @Test("stores step outputs and retrieves them via get/has across phases, overwrites, and edge cases like missing keys or empty outputs", arguments: TestCase.allCases)
    func storeAndRetrieve(_ testCase: TestCase) async {
        let storage = StepOutputsStorage()

        for operation in testCase.operations {
            switch operation {
            case let .store(phase, stepId, outputs):
                await storage.store(phase: phase, stepId: stepId, outputs: outputs)
            case let .expectGet(phase, stepId, key, expectedValue):
                let value = await storage.get(phase: phase, stepId: stepId, key: key)
                #expect(value == expectedValue)
            case let .expectHas(phase, stepId, key, expectedResult):
                let result = await storage.has(phase: phase, stepId: stepId, key: key)
                #expect(result == expectedResult)
            }
        }
    }

    struct TestCase: CustomTestStringConvertible {
        let description: String
        let operations: [Operation]

        static let allCases: [TestCase] = [
            TestCase(
                description: "stores and retrieves outputs",
                operations: [
                    .store(phase: .preHatch, stepId: "setup", outputs: ["version": "1.0.0", "name": "MyApp"]),
                    .expectGet(phase: .preHatch, stepId: "setup", key: "version", expectedValue: "1.0.0"),
                    .expectGet(phase: .preHatch, stepId: "setup", key: "name", expectedValue: "MyApp"),
                ],
            ),
            TestCase(
                description: "returns nil for non-existent output",
                operations: [
                    .expectGet(phase: .preHatch, stepId: "setup", key: "version", expectedValue: nil),
                    .expectGet(phase: .preHatch, stepId: "nonexistent", key: "key", expectedValue: nil),
                ],
            ),
            TestCase(
                description: "checks if output exists",
                operations: [
                    .store(phase: .preHatch, stepId: "setup", outputs: ["version": "1.0.0"]),
                    .expectHas(phase: .preHatch, stepId: "setup", key: "version", expectedResult: true),
                    .expectHas(phase: .preHatch, stepId: "setup", key: "nonexistent", expectedResult: false),
                    .expectHas(phase: .preHatch, stepId: "other", key: "version", expectedResult: false),
                ],
            ),
            TestCase(
                description: "supports cross-phase access",
                operations: [
                    .store(phase: .preHatch, stepId: "setup", outputs: ["version": "1.0.0"]),
                    .store(phase: .postHatch, stepId: "deploy", outputs: ["status": "success"]),
                    .expectGet(phase: .preHatch, stepId: "setup", key: "version", expectedValue: "1.0.0"),
                    .expectGet(phase: .postHatch, stepId: "deploy", key: "status", expectedValue: "success"),
                ],
            ),
            TestCase(
                description: "handles multiple steps in same phase",
                operations: [
                    .store(phase: .preHatch, stepId: "step1", outputs: ["key1": "value1"]),
                    .store(phase: .preHatch, stepId: "step2", outputs: ["key2": "value2"]),
                    .expectGet(phase: .preHatch, stepId: "step1", key: "key1", expectedValue: "value1"),
                    .expectGet(phase: .preHatch, stepId: "step2", key: "key2", expectedValue: "value2"),
                    .expectGet(phase: .preHatch, stepId: "step1", key: "key2", expectedValue: nil),
                ],
            ),
            TestCase(
                description: "overwrites existing output",
                operations: [
                    .store(phase: .preHatch, stepId: "setup", outputs: ["version": "1.0.0"]),
                    .store(phase: .preHatch, stepId: "setup", outputs: ["version": "2.0.0", "new-key": "new-value"]),
                    .expectGet(phase: .preHatch, stepId: "setup", key: "version", expectedValue: "2.0.0"),
                    .expectGet(phase: .preHatch, stepId: "setup", key: "new-key", expectedValue: "new-value"),
                ],
            ),
            TestCase(
                description: "handles empty outputs",
                operations: [
                    .store(phase: .preHatch, stepId: "setup", outputs: [:]),
                    .expectGet(phase: .preHatch, stepId: "setup", key: "any", expectedValue: nil),
                    .expectHas(phase: .preHatch, stepId: "setup", key: "any", expectedResult: false),
                ],
            ),
            TestCase(
                description: "handles special characters in keys",
                operations: [
                    .store(
                        phase: .preHatch,
                        stepId: "setup",
                        outputs: [
                            "src-dir": "/tmp/src",
                            "app.name": "MyApp",
                            "BUILD_TYPE": "DEBUG",
                        ],
                    ),
                    .expectGet(phase: .preHatch, stepId: "setup", key: "src-dir", expectedValue: "/tmp/src"),
                    .expectGet(phase: .preHatch, stepId: "setup", key: "app.name", expectedValue: "MyApp"),
                    .expectGet(phase: .preHatch, stepId: "setup", key: "BUILD_TYPE", expectedValue: "DEBUG"),
                ],
            ),
        ]

        enum Operation {
            case store(phase: LifecyclePhase, stepId: String, outputs: [String: String])
            case expectGet(phase: LifecyclePhase, stepId: String, key: String, expectedValue: String?)
            case expectHas(phase: LifecyclePhase, stepId: String, key: String, expectedResult: Bool)
        }

        var testDescription: String {
            description
        }
    }
}
