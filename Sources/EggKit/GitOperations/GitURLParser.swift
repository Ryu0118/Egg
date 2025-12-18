import Foundation

/// A protocol for parsing Git repository URLs.
package protocol GitURLParsing: Sendable {
    /// Parses a URL string into a GitURL.
    ///
    /// - Parameter urlString: The Git repository URL string to parse
    /// - Returns: A parsed `GitURL` if valid, `nil` otherwise
    func parse(_ urlString: String) -> GitURL?
}

/// Parses Git repository URLs in various formats.
///
/// Supports the following URL formats:
/// - HTTPS: `https://github.com/user/repo.git` or `https://github.com/user/repo`
/// - SSH: `git@github.com:user/repo.git`
/// - Git protocol: `git://github.com/user/repo.git`
package struct GitURLParser: GitURLParsing {
    package init() {}

    package func parse(_ urlString: String) -> GitURL? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return nil
        }

        // SSH format: git@host:user/repo.git
        if isSSHURL(trimmed) {
            return GitURL(original: trimmed, normalized: trimmed)
        }

        // HTTPS or Git protocol
        if isHTTPSURL(trimmed) || isGitProtocolURL(trimmed) {
            return GitURL(original: trimmed, normalized: trimmed)
        }

        return nil
    }

    /// Checks if the URL is in SSH format (git@host:path)
    private func isSSHURL(_ urlString: String) -> Bool {
        // Pattern: git@<host>:<path>.git or git@<host>:<path>
        // Examples:
        //   git@github.com:user/repo.git
        //   git@gitlab.com:group/subgroup/repo.git
        let sshPattern = #"^git@[\w.\-]+:[\w.\-/]+(?:\.git)?$"#
        return urlString.range(of: sshPattern, options: .regularExpression) != nil
    }

    /// Checks if the URL is in HTTPS format
    private func isHTTPSURL(_ urlString: String) -> Bool {
        // Pattern: https://[user:pass@]<host>/<path>.git or https://[user:pass@]<host>/<path>
        // Examples:
        //   https://github.com/user/repo.git
        //   https://github.com/user/repo
        //   https://gitlab.com/group/subgroup/repo.git
        //   https://x-access-token:TOKEN@github.com/user/repo.git (GitHub Actions)
        let httpsPattern = #"^https?://(?:[^@]+@)?[\w.\-]+/[\w.\-/]+(?:\.git)?$"#
        return urlString.range(of: httpsPattern, options: .regularExpression) != nil
    }

    /// Checks if the URL is in Git protocol format
    private func isGitProtocolURL(_ urlString: String) -> Bool {
        // Pattern: git://<host>/<path>.git
        // Examples:
        //   git://github.com/user/repo.git
        let gitPattern = #"^git://[\w.\-]+/[\w.\-/]+(?:\.git)?$"#
        return urlString.range(of: gitPattern, options: .regularExpression) != nil
    }
}
