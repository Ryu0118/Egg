import Foundation
@testable import Interaction
import Testing

private final class ScriptedKeyInput: KeyInput, @unchecked Sendable {
    private var keys: [TerminalKey]

    init(_ keys: [TerminalKey]) {
        self.keys = keys
    }

    func readKey() -> TerminalKey? {
        keys.isEmpty ? nil : keys.removeFirst()
    }
}

private final class ScriptedLineInput: TextInput, @unchecked Sendable {
    private var lines: [String]

    init(_ lines: [String]) {
        self.lines = lines
    }

    func readLine() -> String? {
        lines.isEmpty ? nil : lines.removeFirst()
    }
}

private final class CapturedOutput: TextOutput, @unchecked Sendable {
    private var buffer = ""

    var text: String {
        buffer
    }

    func write(_ text: String) {
        buffer += text
    }
}

private func makeTerminal(
    keys: [TerminalKey] = [],
    lines: [String] = [],
    isInteractive: Bool = true,
) -> (terminal: Terminal, output: CapturedOutput) {
    let output = CapturedOutput()
    let terminal = Terminal(
        input: ScriptedLineInput(lines),
        keyInput: ScriptedKeyInput(keys),
        output: output,
        capabilities: TerminalCapabilities(isInteractive: isInteractive, supportsColor: false),
    )
    return (terminal, output)
}

struct TerminalInteractiveTests {
    @Test func `choose navigates options with arrow keys`() {
        let (terminal, output) = makeTerminal(keys: [.down, .enter])

        let answer = terminal.choose(ChoicePrompt(question: "Pick one", options: ["first", "second", "third"]))

        #expect(answer == "second")
        #expect(output.text.contains("❯"))
        #expect(output.text.contains("Pick one second"))
    }

    @Test func `choose filters options by typed text`() {
        let (terminal, _) = makeTerminal(keys: [.character("b"), .character("a"), .enter])

        let answer = terminal.choose(ChoicePrompt(question: "Pick", options: ["apple", "banana"]))

        #expect(answer == "banana")
    }

    @Test func `chooseMany toggles options with space`() {
        let (terminal, _) = makeTerminal(keys: [.character(" "), .down, .down, .character(" "), .enter])

        let answer = terminal.chooseMany(MultipleChoicePrompt(question: "Pick", options: ["a", "b", "c"]))

        #expect(answer == ["a", "c"])
    }

    @Test func `chooseMany enforces the minimum selection count`() {
        let (terminal, output) = makeTerminal(keys: [.enter, .character(" "), .enter])

        let answer = terminal.chooseMany(
            MultipleChoicePrompt(question: "Pick", options: ["a", "b"], minimumSelectionCount: 1),
        )

        #expect(answer == ["a"])
        #expect(output.text.contains("Select at least 1 option(s)."))
    }

    @Test func `readText edits the buffer with cursor keys`() {
        let (terminal, _) = makeTerminal(
            keys: [.character("a"), .character("b"), .left, .backspace, .character("c"), .enter],
        )

        let answer = terminal.readText(TextPrompt(message: "Name:"))

        #expect(answer == "cb")
    }

    @Test func `readText re-prompts until validation passes`() {
        let (terminal, output) = makeTerminal(keys: [.enter, .character("x"), .enter])

        let answer = terminal.readText(
            TextPrompt(message: "Name:", validationRules: [NonEmptyRule()]),
        )

        #expect(answer == "x")
        #expect(output.text.contains("Input cannot be empty."))
    }

    @Test func `confirm answers with a single key`() {
        let (yesTerminal, _) = makeTerminal(keys: [.enter])
        let (noTerminal, _) = makeTerminal(keys: [.character("n")])

        #expect(yesTerminal.confirm(ConfirmationPrompt(question: "Continue?")) == true)
        #expect(noTerminal.confirm(ConfirmationPrompt(question: "Continue?")) == false)
    }

    @Test func `non-interactive sessions fall back to numbered prompts`() {
        let (terminal, output) = makeTerminal(lines: ["2"], isInteractive: false)

        let answer = terminal.choose(ChoicePrompt(question: "Pick one", options: ["first", "second"]))

        #expect(answer == "second")
        #expect(output.text.contains("1. first"))
    }
}
