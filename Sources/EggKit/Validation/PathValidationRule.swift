import Foundation
import Interaction

package struct PathValidationRule: ValidationRule {
    private let error: ValidationError
    private let workingDirectory: URL
    private let homeDirectory: URL

    package init(workingDirectory: URL, homeDirectory: URL, error: String) {
        self.workingDirectory = workingDirectory
        self.homeDirectory = homeDirectory
        self.error = ValidationError(error)
    }

    package func validate(input: String) -> Bool {
        guard !input.isEmpty else { return false }

        // Try to resolve the path
        do {
            let _ = try PathResolver.resolveToAbsoluteURL(
                input,
                workingDirectory: workingDirectory,
                homeDirectory: homeDirectory,
            )
            return true
        } catch {
            return false
        }
    }

    package func validate(_ input: String) -> ValidationError? {
        validate(input: input) ? nil : error
    }
}
