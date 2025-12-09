import Foundation
import Noora
import Path

package struct PathValidationRule: ValidatableRule {
    package let error: any ValidatableError
    private let workingDirectory: AbsolutePath
    private let homeDirectory: AbsolutePath

    package init(workingDirectory: AbsolutePath, homeDirectory: AbsolutePath, error: String) {
        self.workingDirectory = workingDirectory
        self.homeDirectory = homeDirectory
        self.error = error
    }

    package func validate(input: String) -> Bool {
        guard !input.isEmpty else { return false }

        // Try to resolve the path
        do {
            let _ = try resolveToAbsolutePath(
                input,
                workingDirectory: workingDirectory,
                homeDirectory: homeDirectory
            )
            return true
        } catch {
            return false
        }
    }
}
