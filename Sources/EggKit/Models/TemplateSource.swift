import Foundation

/// Represents the source location of templates to install.
///
/// Templates can be installed from:
/// - A remote Git repository (HTTPS, SSH, or Git protocol)
/// - A local filesystem path (absolute or relative)
package enum TemplateSource: Sendable, Equatable {
    /// A remote Git repository.
    ///
    /// - Parameters:
    ///   - url: The parsed Git URL
    ///   - ref: The Git reference (branch/tag/revision), or `nil` for default branch
    case git(url: GitURL, ref: GitRef?)

    /// A local filesystem path.
    ///
    /// - Parameter path: The absolute path to the local directory containing templates
    case local(path: URL)
}
