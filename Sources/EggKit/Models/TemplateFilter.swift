import Foundation

/// Represents a filter condition for selecting which templates to install.
///
/// Used with `--template` and `--exclude` options in the install command.
package enum TemplateFilter: Equatable, Sendable {
    /// No filtering - all templates will be installed
    case none
    /// Only install templates with the specified names
    case include([String])
    /// Install all templates except those with the specified names
    case exclude([String])

    /// Determines whether a template with the given name should be included.
    ///
    /// - Parameter templateName: The name of the template to check
    /// - Returns: `true` if the template should be included, `false` otherwise
    package func shouldInclude(_ templateName: String) -> Bool {
        switch self {
        case .none:
            true
        case let .include(names):
            names.contains(templateName)
        case let .exclude(names):
            !names.contains(templateName)
        }
    }
}
