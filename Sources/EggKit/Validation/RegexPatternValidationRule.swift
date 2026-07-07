import Foundation
import Interaction

package extension ValidationRule {
    /// Requires the input to match `pattern`.
    static func regexPattern(_ pattern: String, error: String) -> ValidationRule {
        ValidationRule { input in
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                return ValidationError(error)
            }

            let range = NSRange(input.startIndex..., in: input)
            return regex.firstMatch(in: input, range: range) != nil ? nil : ValidationError(error)
        }
    }
}
