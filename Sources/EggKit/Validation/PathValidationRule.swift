import Foundation
import Interaction

package struct PathValidationRule: PredicateValidationRule {
    package let error: ValidationError
    private let workingDirectory: URL
    private let homeDirectory: URL
    private let allowsEmpty: Bool

    package init(workingDirectory: URL, homeDirectory: URL, allowsEmpty: Bool = false, error: String) {
        self.workingDirectory = workingDirectory
        self.homeDirectory = homeDirectory
        self.allowsEmpty = allowsEmpty
        self.error = ValidationError(error)
    }

    package func validate(input: String) -> Bool {
        // An empty input is accepted only when a default value exists to fall
        // back to; otherwise NonEmptyRule (added separately) rejects it. Without
        // this, a path macro with a default could never be accepted by pressing
        // Enter, trapping the user in an infinite prompt loop.
        guard !input.isEmpty else { return allowsEmpty }

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
}
