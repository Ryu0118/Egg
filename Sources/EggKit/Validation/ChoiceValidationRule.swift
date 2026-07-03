import Foundation
import Interaction

package struct ChoiceValidationRule: PredicateValidationRule {
    package let error: ValidationError
    private let choices: [String]

    package init(choices: [String], error: String) {
        self.choices = choices
        self.error = ValidationError(error)
    }

    package func validate(input: String) -> Bool {
        choices.contains(input)
    }
}
