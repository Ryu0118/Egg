import FileManagerProtocol
import Foundation

/// Validates command-line arguments for the `egg template install` command
/// and determines the appropriate runner mode.
package struct InstallArgumentsValidator {
    private let url: String?
    private let branch: String?
    private let tag: String?
    private let revision: String?
    private let templates: [String]
    private let excludeTemplates: [String]
    private let global: Bool
    private let projectDirectory: URL
    private let workingDirectory: URL
    private let homeDirectory: URL
    private let gitURLParser: any GitURLParsing
    private let fileManager: any FileManagerProtocol

    /// Creates a new validator with the given arguments.
    ///
    /// - Parameters:
    ///   - url: The Git repository URL or local path (optional for interactive mode)
    ///   - branch: Branch name to install from (Git sources only)
    ///   - tag: Tag name to install from (Git sources only)
    ///   - revision: Commit SHA to install from (Git sources only)
    ///   - templates: Template names to include (mutually exclusive with excludeTemplates)
    ///   - excludeTemplates: Template names to exclude (mutually exclusive with templates)
    ///   - global: Whether to install globally
    ///   - projectDirectory: The project directory path
    ///   - workingDirectory: The current working directory
    ///   - homeDirectory: The user's home directory
    ///   - gitURLParser: Parser for Git URLs
    ///   - fileManager: File manager for checking local paths
    package init(
        url: String?,
        branch: String?,
        tag: String?,
        revision: String?,
        templates: [String],
        excludeTemplates: [String],
        global: Bool,
        projectDirectory: URL,
        workingDirectory: URL,
        homeDirectory: URL,
        gitURLParser: some GitURLParsing = GitURLParser(),
        fileManager: some FileManagerProtocol = FileManager.default
    ) {
        self.url = url
        self.branch = branch
        self.tag = tag
        self.revision = revision
        self.templates = templates
        self.excludeTemplates = excludeTemplates
        self.global = global
        self.projectDirectory = projectDirectory
        self.workingDirectory = workingDirectory
        self.homeDirectory = homeDirectory
        self.gitURLParser = gitURLParser
        self.fileManager = fileManager
    }

    /// Validates the arguments and returns the appropriate runner mode.
    ///
    /// - Returns: The runner mode (interactive or direct)
    /// - Throws: `Error` if validation fails
    package func validate() async throws -> InstallRunnerMode {
        // If no URL is provided, use interactive mode
        guard let urlString = url else {
            return .interactive
        }

        // Check for mutually exclusive filter options
        if !templates.isEmpty && !excludeTemplates.isEmpty {
            throw Error.mutuallyExclusiveFilterOptions
        }

        // Determine the location type
        let location: TemplateLocationType.Kind = global ? .global : .project

        // Determine the filter
        let filter: TemplateFilter = if !templates.isEmpty {
            .include(templates)
        } else if !excludeTemplates.isEmpty {
            .exclude(excludeTemplates)
        } else {
            .none
        }

        // Try to parse as a local path first
        if let localPath = parseLocalPath(urlString) {
            // Check that ref options are not used with local paths
            let hasRefOptions = branch != nil || tag != nil || revision != nil
            if hasRefOptions {
                throw Error.refOptionsNotAllowedForLocalPath
            }

            return .direct(source: .local(path: localPath), location: location, filter: filter)
        }

        // Try to parse as a Git URL
        guard let gitURL = gitURLParser.parse(urlString) else {
            throw Error.invalidSourcePath(urlString)
        }

        // Check for mutually exclusive ref options
        let refOptions = [branch, tag, revision].compactMap { $0 }
        if refOptions.count > 1 {
            throw Error.mutuallyExclusiveRefOptions
        }

        // Determine the Git ref
        let ref: GitRef? = if let branch {
            .branch(branch)
        } else if let tag {
            .tag(tag)
        } else if let revision {
            .revision(revision)
        } else {
            nil
        }

        return .direct(source: .git(url: gitURL, ref: ref), location: location, filter: filter)
    }

    /// Attempts to parse the input string as a local filesystem path.
    ///
    /// Recognizes the following path formats:
    /// - Absolute paths: `/path/to/templates`
    /// - Home-relative paths: `~/templates`
    /// - Relative paths: `./templates`, `../templates`, `path/to/templates`
    ///
    /// For paths that don't start with `/`, `~/`, `./`, or `../`, we check if
    /// the path exists relative to the working directory before trying Git URL parsing.
    ///
    /// - Parameter input: The input string to parse
    /// - Returns: The resolved absolute path URL if valid, `nil` otherwise
    private func parseLocalPath(_ input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return nil
        }

        let resolvedPath: URL

        if trimmed.hasPrefix("/") {
            // Absolute path
            resolvedPath = URL(filePath: trimmed, directoryHint: .isDirectory)
        } else if trimmed.hasPrefix("~/") {
            // Home-relative path
            let relativePath = String(trimmed.dropFirst(2))
            resolvedPath = homeDirectory.appending(path: relativePath, directoryHint: .isDirectory)
        } else {
            // Relative path (including ./foo, ../foo, and plain foo/bar)
            resolvedPath = workingDirectory.appending(path: trimmed, directoryHint: .isDirectory)
                .standardized
        }

        // Check if the path exists and is a directory
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: resolvedPath.path(percentEncoded: false), isDirectory: &isDirectory)

        guard exists, isDirectory.boolValue else {
            return nil
        }

        return resolvedPath
    }

    /// Errors that can occur during argument validation.
    enum Error: LocalizedError, Equatable {
        /// The provided path is neither a valid Git URL nor an existing local directory
        case invalidSourcePath(String)
        /// Multiple ref options (--branch, --tag, --revision) were specified
        case mutuallyExclusiveRefOptions
        /// Both --template and --exclude options were specified
        case mutuallyExclusiveFilterOptions
        /// Ref options (--branch, --tag, --revision) were used with a local path
        case refOptionsNotAllowedForLocalPath

        var errorDescription: String? {
            switch self {
            case let .invalidSourcePath(path):
                "Invalid source: '\(path)' is neither a valid Git URL nor an existing local directory"
            case .mutuallyExclusiveRefOptions:
                "Only one of --branch, --tag, or --revision can be specified"
            case .mutuallyExclusiveFilterOptions:
                "Cannot use both --template and --exclude options together"
            case .refOptionsNotAllowedForLocalPath:
                "Options --branch, --tag, and --revision are not allowed when installing from a local path"
            }
        }
    }
}
