import Interaction

/// Interaction for service-mode runners whose stdout must stay pure JSON
/// (the CLI's `--json` paths and MCP tool handlers): progress writes are
/// swallowed so they can't interleave with the encoded result, and reaching
/// a prompt fails fast — service mode is non-interactive by contract.
struct SilentInteraction: InteractionProviding {
    private let prompts = GuardedTerminal(isTTY: { false })

    func write(_: StyledText) {}

    func writeStatus(_: Status, _: StyledText) {}

    func writeTable(_: Table) {}

    func readText(_ prompt: TextPrompt) -> String {
        prompts.readText(prompt)
    }

    func confirm(_ prompt: ConfirmationPrompt) -> Bool {
        prompts.confirm(prompt)
    }

    func choose<Option>(_ prompt: ChoicePrompt<Option>) -> Option {
        prompts.choose(prompt)
    }

    func chooseMany<Option>(_ prompt: MultipleChoicePrompt<Option>) -> [Option] {
        prompts.chooseMany(prompt)
    }
}
