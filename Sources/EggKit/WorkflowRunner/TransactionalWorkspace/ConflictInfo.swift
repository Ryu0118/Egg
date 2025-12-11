import Foundation
import Path

/// Information about a conflict detected during transactional workspace apply.
struct ConflictInfo: Equatable, Sendable {
    let path: RelativePath
    let type: ConflictType

    /// Type of conflict detected.
    enum ConflictType: Equatable, Sendable {
        /// File was modified in transactional workspace but also modified in working directory.
        case bothModified
        /// File was deleted in transactional workspace but modified in working directory.
        case deletedButModified

        var description: String {
            switch self {
            case .bothModified:
                return "modified in both transactional workspace and working directory"
            case .deletedButModified:
                return "deleted in transactional workspace but modified in working directory"
            }
        }
    }
}
