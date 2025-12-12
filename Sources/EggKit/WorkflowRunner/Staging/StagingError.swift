import Foundation

/// Errors that can occur during staging operations.
extension StagingContext {
    enum Error: LocalizedError, Equatable {
        /// Attempted to use a staging area that has already been discarded.
        case alreadyDiscarded

        /// Failed to create staging directory structure.
        case creationFailed(reason: String)

        /// Path attempted to escape staging boundaries.
        /// This can occur in pre_hatch, hatch output, or post_hatch.
        case escapeAttempt(path: String)

        /// Conflicting changes detected during apply.
        /// Contains list of conflicting relative paths and conflict type.
        case conflictingFiles([ConflictInfo])

        /// User declined to apply changes when prompted.
        case userAborted

        /// Git diff command failed with a non-zero exit code.
        case gitDiffFailed(exitCode: Int32)

        /// Git diff process crashed unexpectedly.
        case gitDiffCrashed

        var errorDescription: String? {
            switch self {
            case .alreadyDiscarded:
                return "Staging area has already been discarded"
            case let .creationFailed(reason):
                return "Failed to create staging area: \(reason)"
            case let .escapeAttempt(path):
                return "Path escape attempt detected: \(path)"
            case let .conflictingFiles(conflicts):
                var message = "Conflicting changes detected:\n"
                for conflict in conflicts {
                    message += "  - \(conflict.pathString): \(conflict.type.description)\n"
                }
                message += "Please resolve conflicts manually and retry, or use --override to apply staged changes."
                return message
            case .userAborted:
                return "Operation cancelled by user"
            case let .gitDiffFailed(exitCode):
                return "git diff failed with exit code \(exitCode)"
            case .gitDiffCrashed:
                return "git diff crashed while computing change summary"
            }
        }
    }
}
