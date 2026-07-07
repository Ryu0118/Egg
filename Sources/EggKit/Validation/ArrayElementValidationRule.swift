import Foundation
import Interaction

package extension ValidationRule {
    /// Validates that each element in a comma-separated array matches a regex pattern.
    static func arrayElement(elementPattern: String, error: String) -> ValidationRule {
        ValidationRule { input in
            let parser = ArrayInputParser()
            let elements = parser.parseFromInteractive(input)

            guard let regex = try? NSRegularExpression(pattern: elementPattern) else {
                return ValidationError(error)
            }

            for element in elements {
                let range = NSRange(element.startIndex..., in: element)
                guard regex.firstMatch(in: element, range: range) != nil else {
                    return ValidationError(error)
                }
            }

            return nil
        }
    }
}
