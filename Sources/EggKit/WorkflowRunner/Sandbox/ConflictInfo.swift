import Foundation
import Path

/// Information about a conflict detected during sandbox apply.
struct ConflictInfo: Equatable, Sendable {
    let path: RelativePath
    let type: ConflictType

    /// Type of conflict detected.
    enum ConflictType: Equatable, Sendable {
        /// File was modified in sandbox but also modified in working directory.
        case bothModified
        /// File was deleted in sandbox but modified in working directory.
        case deletedButModified

        var description: String {
            switch self {
            case .bothModified:
                return "modified in both sandbox and working directory"
            case .deletedButModified:
                return "deleted in sandbox but modified in working directory"
            }
        }
    }
}
