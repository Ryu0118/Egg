import Foundation
import Path

/// Information about a conflict detected during staging apply.
struct ConflictInfo: Equatable, Sendable {
    let path: RelativePath
    let type: ConflictType

    /// Type of conflict detected.
    enum ConflictType: Equatable, Sendable {
        /// File was modified in staging but also modified in working directory.
        case bothModified
        /// File was deleted in staging but modified in working directory.
        case deletedButModified

        var description: String {
            switch self {
            case .bothModified:
                return "modified in both staging and working directory"
            case .deletedButModified:
                return "deleted in staging but modified in working directory"
            }
        }
    }
}
