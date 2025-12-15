import Foundation

/// Represents a template discovered from a cloned Git repository.
///
/// Contains all the information needed to install a template:
/// the template name (derived from directory name), source location,
/// and validated configuration.
struct DiscoveredTemplate {
    /// The template name (directory name in the repository)
    let name: String

    /// The source directory containing the template files
    let sourceDirectory: URL

    /// The parsed and validated template configuration
    let config: Config
}
