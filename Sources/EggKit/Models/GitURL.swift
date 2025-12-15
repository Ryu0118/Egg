import Foundation

/// Represents a parsed Git repository URL.
///
/// Contains both the original URL string and a normalized version suitable for `git clone`.
package struct GitURL: Equatable, Sendable {
    /// The original URL string as provided by the user
    package let original: String
    /// The normalized URL suitable for git clone command
    package let normalized: String

    package init(original: String, normalized: String) {
        self.original = original
        self.normalized = normalized
    }
}
