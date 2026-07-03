import Interaction

struct TestInteraction: InteractionProviding {
    private let textAnswers: [String]
    private let confirmationAnswers: [Bool]

    init(
        textAnswers: [String] = [],
        confirmationAnswers: [Bool] = [],
    ) {
        self.textAnswers = textAnswers
        self.confirmationAnswers = confirmationAnswers
    }

    func write(_: StyledText) {}

    func writeStatus(_: Status, _: StyledText) {}

    func writeTable(_: Table) {}

    func readText(_: TextPrompt) -> String {
        guard let answer = textAnswers.first else {
            preconditionFailure("TestInteraction.readText was called without a configured answer.")
        }
        return answer
    }

    func confirm(_: ConfirmationPrompt) -> Bool {
        guard let answer = confirmationAnswers.first else {
            preconditionFailure("TestInteraction.confirm was called without a configured answer.")
        }
        return answer
    }

    func choose<Option>(_: ChoicePrompt<Option>) -> Option {
        preconditionFailure("TestInteraction.choose was called without a configured answer.")
    }

    func chooseMany<Option>(_: MultipleChoicePrompt<Option>) -> [Option] {
        preconditionFailure("TestInteraction.chooseMany was called without a configured answer.")
    }
}
