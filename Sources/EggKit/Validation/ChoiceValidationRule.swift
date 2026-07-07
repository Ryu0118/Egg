import Foundation
import Interaction

package extension ValidationRule {
    /// Requires the input to be one of `choices`.
    static func choice(choices: [String], error: String) -> ValidationRule {
        ValidationRule { input in
            choices.contains(input) ? nil : ValidationError(error)
        }
    }
}
