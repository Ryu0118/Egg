import Foundation

/// Represents a Git reference (branch, tag, or commit SHA).
///
/// Used to specify which version of a repository to clone when installing templates.
/// When `nil` is used instead of a `GitRef`, Git will automatically select the default branch.
package enum GitRef: Equatable, Sendable, Codable {
    /// A branch reference (e.g., "main", "develop")
    case branch(String)
    /// A tag reference (e.g., "v1.0.0")
    case tag(String)
    /// A specific commit SHA (e.g., "abc123")
    case revision(String)

    /// The ref value as a string
    package var value: String {
        switch self {
        case let .branch(name): name
        case let .tag(name): name
        case let .revision(sha): sha
        }
    }
}
