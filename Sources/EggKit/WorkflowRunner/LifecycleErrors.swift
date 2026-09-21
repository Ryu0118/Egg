import Foundation

enum LifecycleStepError: LocalizedError, Equatable {
    /// A `run:` step exited non-zero.
    ///
    /// `stdout` carries what the step printed before failing — usually the
    /// most useful thing there is for diagnosing it. This error is the only
    /// place that output can travel: the step's result object never comes
    /// into existence, so anything not carried here is lost.
    case shellExecutionError(command: String, exitCode: Int32, stdout: String, stderr: String)
    case undefinedOutputReference(phase: LifecyclePhase, stepId: String, key: String)
    case conditionEvaluationError(condition: String, reason: String)
    case invalidOutputDirectory(String)
    case sandboxPermissionRequired(paths: [String])

    var errorDescription: String? {
        switch self {
        case let .shellExecutionError(command, exitCode, stdout, stderr):
            """
            Shell command failed with exit code \(exitCode): \(command)
            stdout: \(Self.truncateForDisplay(stdout))
            stderr: \(stderr)
            """
        case let .undefinedOutputReference(phase, stepId, key):
            "Undefined output reference: \(phase.rawValue).\(stepId).outputs.\(key)"
        case let .conditionEvaluationError(condition, reason):
            "Failed to evaluate condition '\(condition)': \(reason)"
        case let .invalidOutputDirectory(message):
            "Invalid output directory: \(message)"
        case let .sandboxPermissionRequired(paths):
            """
            ⚠️ SANDBOX EXTENDED WRITE ACCESS REQUIRED

            This template requires write access to paths outside the sandbox:
            \(paths.map { "  - \($0)" }.joined(separator: "\n"))

            To proceed:
            1. Run in interactive mode: egg hatch <template_name>
            2. Or use --no-sandbox flag with explicit user permission
            """
        }
    }

    /// Caps a failing step's stdout for display.
    ///
    /// Keeps the **tail**, unlike `LifecycleScriptOutput`, which keeps the
    /// head: there the interesting content is an author's message written up
    /// front, here it is whatever the command said just before it died.
    private static func truncateForDisplay(_ stdout: String) -> String {
        let bytes = Array(stdout.utf8)
        guard bytes.count > LifecycleScriptOutput.byteLimit else {
            return stdout
        }
        let tail = String(decoding: bytes.suffix(LifecycleScriptOutput.byteLimit), as: UTF8.self)
        return "…(truncated)\n\(tail)"
    }
}
