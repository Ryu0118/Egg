import Foundation

enum LifecycleStepError: LocalizedError, Equatable {
    case shellExecutionError(command: String, exitCode: Int32, stderr: String)
    case undefinedOutputReference(phase: LifecyclePhase, stepId: String, key: String)
    case conditionEvaluationError(condition: String, reason: String)

    var errorDescription: String? {
        switch self {
        case let .shellExecutionError(command, exitCode, stderr):
            """
            Shell command failed with exit code \(exitCode): \(command)
            stderr: \(stderr)
            """
        case let .undefinedOutputReference(phase, stepId, key):
            "Undefined output reference: \(phase.rawValue).\(stepId).outputs.\(key)"
        case let .conditionEvaluationError(condition, reason):
            "Failed to evaluate condition '\(condition)': \(reason)"
        }
    }
}
