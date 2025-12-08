import Foundation
import Noora

package struct RegexPatternValidationRule: ValidatableRule {
    package let error: any ValidatableError
    private let pattern: String

    package init(pattern: String, error: String) {
        self.pattern = pattern
        self.error = error
    }

    package func validate(input: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return false
        }

        let range = NSRange(input.startIndex..., in: input)
        return regex.firstMatch(in: input, range: range) != nil
    }
}
