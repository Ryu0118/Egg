import Foundation

/// Represents the mode of operation for the install runner.
///
/// - `interactive`: The user will be prompted for input through the CLI.
/// - `direct`: All required parameters are provided via command-line arguments.
package enum InstallRunnerMode: Sendable {
    /// Interactive mode where the user will be prompted for:
    /// - Git repository URL or local path
    /// - Branch, tag, or commit (optional, for Git sources only)
    /// - Installation location (global or project)
    /// - Templates to install
    case interactive

    /// Direct mode where all parameters are provided via command-line arguments.
    ///
    /// - Parameters:
    ///   - source: The template source (Git repository or local path)
    ///   - location: Where to install templates (global or project)
    ///   - filter: Which templates to include or exclude
    case direct(source: TemplateSource, location: TemplateLocationType.Kind, filter: TemplateFilter)
}
