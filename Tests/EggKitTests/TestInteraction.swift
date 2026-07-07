import Interaction

/// A no-op `InteractionProviding` for tests that never expect a prompt.
///
/// Runners under test operate in non-interactive mode, so any prompt call
/// here indicates a test setup bug rather than expected behavior.
struct TestInteraction: InteractionProviding {
    func write(_: StyledText) {}

    func writeStatus(_: Status, _: StyledText) {}

    func writeTable(_: Table) {}

    func readText(_: TextPrompt) async -> String {
        preconditionFailure("TestInteraction.readText was called without a configured answer.")
    }

    func confirm(_: ConfirmationPrompt) -> Bool {
        preconditionFailure("TestInteraction.confirm was called without a configured answer.")
    }

    func choose<Option>(_: ChoicePrompt<Option>) -> Option {
        preconditionFailure("TestInteraction.choose was called without a configured answer.")
    }

    func chooseMany<Option>(_: MultipleChoicePrompt<Option>) -> [Option] {
        preconditionFailure("TestInteraction.chooseMany was called without a configured answer.")
    }
}
