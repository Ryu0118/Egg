import Foundation
import Noora

package struct PathValidationRule: ValidatableRule {
    package let error: any ValidatableError
    private let workingDirectory: URL
    private let homeDirectory: URL

    package init(workingDirectory: URL, homeDirectory: URL, error: String) {
        self.workingDirectory = workingDirectory
        self.homeDirectory = homeDirectory
        self.error = error
    }

    package func validate(input: String) -> Bool {
        guard !input.isEmpty else { return false }

        // Try to resolve the path
        do {
            let _ = try resolveToAbsoluteURL(
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
