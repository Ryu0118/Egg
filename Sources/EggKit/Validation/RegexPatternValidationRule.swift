import Foundation
import Interaction

package struct RegexPatternValidationRule: ValidationRule {
    private let error: ValidationError
    private let pattern: String

    package init(pattern: String, error: String) {
        self.pattern = pattern
        self.error = ValidationError(error)
    }

    package func validate(input: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return false
        }

        let range = NSRange(input.startIndex..., in: input)
        return regex.firstMatch(in: input, range: range) != nil
    }

    package func validate(_ input: String) -> ValidationError? {
        validate(input: input) ? nil : error
    }
}
