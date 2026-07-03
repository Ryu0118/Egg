import Foundation

/// Capabilities of the terminal session attached to the current process.
public struct TerminalCapabilities: Equatable, Sendable {
    /// Whether prompts can use raw-mode interactive input.
    public let isInteractive: Bool
    /// Whether ANSI color codes should be emitted.
    public let supportsColor: Bool

    public init(isInteractive: Bool, supportsColor: Bool) {
        self.isInteractive = isInteractive
        self.supportsColor = supportsColor
    }

    /// Capabilities detected from the standard streams and environment.
    public static func detect(environment: [String: String] = ProcessInfo.processInfo.environment) -> TerminalCapabilities {
        let stdinIsTTY = isatty(STDIN_FILENO) == 1
        let stdoutIsTTY = isatty(STDOUT_FILENO) == 1
        let isDumb = environment["TERM"] == "dumb"
        let noColor = environment["NO_COLOR"].map { !$0.isEmpty } ?? false

        return TerminalCapabilities(
            isInteractive: stdinIsTTY && stdoutIsTTY && !isDumb,
            supportsColor: stdoutIsTTY && !isDumb && !noColor,
        )
    }
}
