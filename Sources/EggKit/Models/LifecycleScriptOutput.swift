import Foundation

/// What one lifecycle step printed on stdout, tagged with where it ran.
///
/// Lifecycle scripts are how a template author talks to whoever is hatching:
/// "run `pnpm install` next", "a config was left at X". In the interactive CLI
/// that message reaches a human because the step's stdout is streamed to the
/// terminal. The agent transaction flow (``AgentHatchPreviewResult``) has to
/// keep stdout free for its JSON, so the streamed lines are suppressed there —
/// and the message used to vanish entirely. Collecting it into the result is
/// what makes the same message reach an agent.
///
/// One entry is recorded per step that egg actually reached, including steps
/// skipped by their `if:` condition, so an agent can tell "this step printed
/// nothing" from "this step never ran".
public struct LifecycleScriptOutput: Codable, Sendable, Equatable {
    /// The phase that ran the step: `pre_hatch` or `post_hatch`.
    ///
    /// The `hatch` phase is pure template expansion and has no script steps,
    /// so it never appears here.
    public let phase: String

    /// The step's zero-based position within its phase, matching the `run`
    /// list order in the template's `egg.yml`.
    public let index: Int

    /// The step's declared `id`, when it has one. Steps without an `id` are
    /// identified by ``phase`` plus ``index`` alone.
    public let id: String?

    /// Everything the step printed on stdout, verbatim — not the parsed
    /// `key=value` step outputs, which stay in their own namespace.
    ///
    /// Empty when the step printed nothing or was skipped.
    public let stdout: String

    /// Whether ``stdout`` was cut at ``LifecycleScriptOutput/byteLimit``.
    ///
    /// A `pre_hatch` step running a build can print megabytes; the cap keeps
    /// the JSON result a reasonable size. What survives is the *beginning* of
    /// the output, because a template author's message is written before the
    /// noise, not after it.
    public let truncated: Bool

    /// Whether the step was skipped because its `if:` condition was false.
    /// A skipped step has empty ``stdout`` and never ran a command.
    public let skipped: Bool

    /// Maximum number of stdout bytes retained per step.
    public static let byteLimit = 64 * 1024

    public init(
        phase: String,
        index: Int,
        id: String?,
        stdout: String,
        truncated: Bool = false,
        skipped: Bool = false,
    ) {
        self.phase = phase
        self.index = index
        self.id = id
        self.stdout = stdout
        self.truncated = truncated
        self.skipped = skipped
    }
}
