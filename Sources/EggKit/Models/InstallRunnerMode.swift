import Foundation

/// Represents the mode of operation for the install runner.
///
/// - `interactive`: The user will be prompted for input through the CLI.
/// - `direct`: All required parameters are provided via command-line arguments.
package enum InstallRunnerMode: Sendable {
    /// Interactive mode where the user will be prompted for:
    /// - Git repository URL
    /// - Branch, tag, or commit (optional)
    /// - Installation location (global or project)
    /// - Templates to install
    case interactive

    /// Direct mode where all parameters are provided via command-line arguments.
    ///
    /// - Parameters:
    ///   - url: The parsed Git URL
    ///   - ref: The Git reference (branch/tag/revision), or `nil` for default branch
    ///   - location: Where to install templates (global or project)
    ///   - filter: Which templates to include or exclude
    case direct(url: GitURL, ref: GitRef?, location: TemplateLocationType.Kind, filter: TemplateFilter)
}
