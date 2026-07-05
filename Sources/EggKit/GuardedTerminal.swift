import Foundation
import Interaction

/// egg's default interaction: a plain `Terminal` while stdin is a TTY, and a
/// fail-fast guard when it is not.
///
/// Agents and CI pipe or close stdin, so an interactive prompt would either
/// hang forever waiting for keystrokes or spin on end-of-input errors —
/// invisible to the caller either way. When a prompt is reached without a
/// TTY, this fails loudly instead: it prints the prompt's own question plus a
/// pointer at the non-interactive alternatives, and exits non-zero.
///
/// Output methods (`write`, `writeStatus`, `writeTable`) pass through
/// unconditionally — only *input* requires a TTY.
public struct GuardedTerminal: InteractionProviding {
    private let base = Terminal()
    private let isTTY: @Sendable () -> Bool

    public init(isTTY: @escaping @Sendable () -> Bool = { isatty(STDIN_FILENO) != 0 }) {
        self.isTTY = isTTY
    }

    public func write(_ text: StyledText) {
        base.write(text)
    }

    public func writeStatus(_ status: Status, _ message: StyledText) {
        base.writeStatus(status, message)
    }

    public func writeTable(_ table: Table) {
        base.writeTable(table)
    }

    public func readText(_ prompt: TextPrompt) -> String {
        guardInteractive(question: prompt.message.plainText)
        return base.readText(prompt)
    }

    public func confirm(_ prompt: ConfirmationPrompt) -> Bool {
        guardInteractive(question: prompt.question.plainText)
        return base.confirm(prompt)
    }

    public func choose<Option>(_ prompt: ChoicePrompt<Option>) -> Option {
        guardInteractive(question: prompt.question.plainText)
        return base.choose(prompt)
    }

    public func chooseMany<Option>(_ prompt: MultipleChoicePrompt<Option>) -> [Option] {
        guardInteractive(question: prompt.question.plainText)
        return base.chooseMany(prompt)
    }

    /// The message shown when a prompt is reached without a TTY. Split out so
    /// tests can pin the wording without triggering the process exit.
    static func nonInteractiveFailureMessage(question: String) -> String {
        """
        Error: interactive input required (\"\(question)\"), but stdin is not a TTY.
        Pass the missing value as a command-line flag instead — run the command with --help to see the options.
        Agents should use the non-interactive transaction flow: egg hatch preview / apply / rollback / discard / transactions.
        """
    }

    private func guardInteractive(question: String) {
        guard !isTTY() else { return }
        FileHandle.standardError.write(Data((Self.nonInteractiveFailureMessage(question: question) + "\n").utf8))
        exit(EX_USAGE)
    }
}
