import Foundation
import Interaction

package extension ValidationRule {
    /// Requires the input to resolve to an absolute path.
    ///
    /// An empty input is accepted only when `allowsEmpty` is set (a default
    /// value exists to fall back to); otherwise `.nonEmpty` (added
    /// separately) rejects it. Without this, a path macro with a default
    /// could never be accepted by pressing Enter, trapping the user in an
    /// infinite prompt loop.
    static func path(workingDirectory: URL, homeDirectory: URL, allowsEmpty: Bool = false, error: String) -> ValidationRule {
        ValidationRule { input in
            guard !input.isEmpty else {
                return allowsEmpty ? nil : ValidationError(error)
            }

            guard (try? PathResolver.resolveToAbsoluteURL(
                input,
                workingDirectory: workingDirectory,
                homeDirectory: homeDirectory,
            )) != nil else {
                return ValidationError(error)
            }
            return nil
        }
    }
}
