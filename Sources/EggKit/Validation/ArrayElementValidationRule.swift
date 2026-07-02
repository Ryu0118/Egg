import Foundation
import Interaction

/// Validates that each element in a comma-separated array matches a regex pattern.
package struct ArrayElementValidationRule: ValidationRule {
    private let error: ValidationError
    private let elementPattern: String

    package init(elementPattern: String, error: String) {
        self.elementPattern = elementPattern
        self.error = ValidationError(error)
    }

    package func validate(input: String) -> Bool {
        let parser = ArrayInputParser()
        let elements = parser.parseFromInteractive(input)

        guard let regex = try? NSRegularExpression(pattern: elementPattern) else {
            return false
        }

        for element in elements {
            let range = NSRange(element.startIndex..., in: element)
            guard regex.firstMatch(in: element, range: range) != nil else {
                return false
            }
        }

        return true
    }

    package func validate(_ input: String) -> ValidationError? {
        validate(input: input) ? nil : error
    }
}
