import Foundation
import Interaction

package extension ValidationRule {
    /// Rejects input that can't be used as a single path component on macOS/Unix.
    static func directoryName(error: String) -> ValidationRule {
        ValidationRule { input in
            guard !input.isEmpty else { return ValidationError(error) }

            let reservedNames = [".", ".."]
            if reservedNames.contains(input) {
                return ValidationError(error)
            }

            if input.contains("/") || input.contains("\0") {
                return ValidationError(error)
            }

            if input.first?.isWhitespace == true {
                return ValidationError(error)
            }

            return nil
        }
    }
}
