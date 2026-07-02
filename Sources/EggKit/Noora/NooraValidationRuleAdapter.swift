import Interaction
import Noora

package final class NooraValidationRuleAdapter: ValidatableRule {
    private let rule: any Interaction.ValidationRule
    private var currentError: any ValidatableError

    package init(_ rule: any Interaction.ValidationRule) {
        self.rule = rule
        currentError = NooraValidationError("Invalid input.")
    }

    package var error: any ValidatableError {
        currentError
    }

    package func validate(input: String) -> Bool {
        guard let error = rule.validate(input) else {
            return true
        }

        currentError = NooraValidationError(error.message)
        return false
    }
}

private struct NooraValidationError: ValidatableError {
    let message: String

    init(_ message: String) {
        self.message = message
    }
}
