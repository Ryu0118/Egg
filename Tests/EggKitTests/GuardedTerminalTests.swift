@testable import EggKit
import Testing

@Suite("GuardedTerminal fails fast instead of prompting without a TTY")
struct GuardedTerminalTests {
    @Test("The failure message carries the prompt's question and the non-interactive alternatives")
    func theFailureMessageCarriesTheQuestionAndAlternatives() {
        let message = GuardedTerminal.nonInteractiveFailureMessage(question: "Which template would you like to use?")

        #expect(message.contains("Which template would you like to use?"))
        #expect(message.contains("stdin is not a TTY"))
        #expect(message.contains("--help"))
        #expect(message.contains("egg hatch preview"))
    }
}
