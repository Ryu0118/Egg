import Foundation
import Interaction

package struct ChoiceValidationRule: ValidationRule {
    private let error: ValidationError
    private let choices: [String]

    package init(choices: [String], error: String) {
        self.choices = choices
        self.error = ValidationError(error)
    }

    package func validate(input: String) -> Bool {
        choices.contains(input)
    }

    package func validate(_ input: String) -> ValidationError? {
        validate(input: input) ? nil : error
    }
}
