import Foundation
import Interaction

package struct DirectoryNameValidationRule: ValidationRule {
    private let error: ValidationError

    package init(error: String) {
        self.error = ValidationError(error)
    }

    package func validate(input: String) -> Bool {
        // Check if input is empty
        guard !input.isEmpty else { return false }

        // Reserved names on macOS/Unix
        let reservedNames = [".", ".."]
        if reservedNames.contains(input) {
            return false
        }

        // Check for invalid characters (macOS: only / and null character are forbidden)
        if input.contains("/") || input.contains("\0") {
            return false
        }

        // Check if name starts with whitespace (can cause issues)
        if input.first?.isWhitespace == true {
            return false
        }

        return true
    }

    package func validate(_ input: String) -> ValidationError? {
        validate(input: input) ? nil : error
    }
}
