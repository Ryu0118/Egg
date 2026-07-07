import Foundation
import Interaction

package extension ValidationRule {
    /// Requires the input's character count to fall within `minLength...maxLength`.
    static func length(minLength: Int, maxLength: Int, error: String) -> ValidationRule {
        ValidationRule { input in
            (minLength ... maxLength).contains(input.count) ? nil : ValidationError(error)
        }
    }

    static var templateNameLength: ValidationRule {
        .length(
            minLength: 1,
            maxLength: 100,
            error: "Template name must be between 1 and 100 characters.",
        )
    }

    static var descriptionLength: ValidationRule {
        .length(
            minLength: 1,
            maxLength: 5000,
            error: "Description must be between 1 and 5000 characters.",
        )
    }
}
