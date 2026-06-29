import Foundation
import Noora

package struct ChoiceValidationRule: ValidatableRule {
    package let error: any ValidatableError
    private let choices: [String]

    package init(choices: [String], error: String) {
        self.choices = choices
        self.error = error
    }

    package func validate(input: String) -> Bool {
        choices.contains(input)
    }
}
