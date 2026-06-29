import Foundation

/// Information about a conflict detected during staging apply.
struct ConflictInfo: Equatable {
    let pathString: String
    let type: ConflictType

    /// Type of conflict detected.
    enum ConflictType: Equatable {
        /// File was modified in staging but also modified in working directory.
        case bothModified
        /// File was deleted in staging but modified in working directory.
        case deletedButModified

        var description: String {
            switch self {
            case .bothModified:
                "modified in both staging and working directory"
            case .deletedButModified:
                "deleted in staging but modified in working directory"
            }
        }
    }
}
