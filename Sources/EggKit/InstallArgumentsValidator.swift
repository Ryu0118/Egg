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

    /// Creates a new validator with the given arguments.
    ///
    /// - Parameters:
    ///   - url: The Git repository URL (optional for interactive mode)
    ///   - branch: Branch name to install from
    ///   - tag: Tag name to install from
    ///   - revision: Commit SHA to install from
    ///   - templates: Template names to include (mutually exclusive with excludeTemplates)
    ///   - excludeTemplates: Template names to exclude (mutually exclusive with templates)
    ///   - global: Whether to install globally
    ///   - projectDirectory: The project directory path
    ///   - workingDirectory: The current working directory
    ///   - homeDirectory: The user's home directory
    ///   - gitURLParser: Parser for Git URLs
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
        gitURLParser: some GitURLParsing = GitURLParser()
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

        // Parse the URL
        guard let gitURL = gitURLParser.parse(urlString) else {
            throw Error.invalidURL(urlString)
        }

        // Check for mutually exclusive ref options
        let refOptions = [branch, tag, revision].compactMap { $0 }
        if refOptions.count > 1 {
            throw Error.mutuallyExclusiveRefOptions
        }

        // Check for mutually exclusive filter options
        if !templates.isEmpty && !excludeTemplates.isEmpty {
            throw Error.mutuallyExclusiveFilterOptions
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

        return .direct(url: gitURL, ref: ref, location: location, filter: filter)
    }

    /// Errors that can occur during argument validation.
    enum Error: LocalizedError, Equatable {
        /// The provided URL is not a valid Git URL
        case invalidURL(String)
        /// Multiple ref options (--branch, --tag, --revision) were specified
        case mutuallyExclusiveRefOptions
        /// Both --template and --exclude options were specified
        case mutuallyExclusiveFilterOptions

        var errorDescription: String? {
            switch self {
            case let .invalidURL(url):
                "Invalid Git URL: \(url)"
            case .mutuallyExclusiveRefOptions:
                "Only one of --branch, --tag, or --revision can be specified"
            case .mutuallyExclusiveFilterOptions:
                "Cannot use both --template and --exclude options together"
            }
        }
    }
}
