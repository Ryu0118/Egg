import Foundation

/// Accumulates the stdout of every lifecycle step a run reaches, so a
/// non-interactive caller can surface it in its JSON result.
///
/// The collector is passed down per call rather than held by the runners,
/// because a failed workflow still needs the records of the steps that ran
/// before the failure — the caller owns it and reads it either way.
actor LifecycleScriptOutputCollector {
    private var entries: [LifecycleScriptOutput] = []

    /// Records a step that was skipped by its `if:` condition.
    func recordSkipped(phase: LifecyclePhase, index: Int, id: String?) {
        entries.append(
            LifecycleScriptOutput(phase: phase.rawValue, index: index, id: id, stdout: "", skipped: true),
        )
    }

    /// Records a step that ran, with whatever it printed.
    ///
    /// `stdout` is capped at ``LifecycleScriptOutput/byteLimit``; the retained
    /// prefix is decoded leniently so a cut multi-byte sequence degrades to a
    /// replacement character instead of dropping the whole chunk.
    func record(phase: LifecyclePhase, index: Int, id: String?, stdout: String) {
        guard stdout.utf8.count > LifecycleScriptOutput.byteLimit else {
            entries.append(
                LifecycleScriptOutput(phase: phase.rawValue, index: index, id: id, stdout: stdout),
            )
            return
        }

        let retained = Array(stdout.utf8.prefix(LifecycleScriptOutput.byteLimit))
        entries.append(
            LifecycleScriptOutput(
                phase: phase.rawValue,
                index: index,
                id: id,
                stdout: String(decoding: retained, as: UTF8.self),
                truncated: true,
            ),
        )
    }

    /// Everything recorded so far, in execution order.
    func drain() -> [LifecycleScriptOutput] {
        entries
    }
}
