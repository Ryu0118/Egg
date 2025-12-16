import Foundation

/// The result of installing templates from a repository.
package struct InstallResult: Sendable {
    /// Names of templates that were successfully installed.
    package let installed: [String]

    /// Templates that were skipped during installation.
    package let skipped: [SkippedTemplate]

    /// Templates that failed to install.
    package let failed: [FailedTemplate]

    package init(
        installed: [String],
        skipped: [SkippedTemplate],
        failed: [FailedTemplate]
    ) {
        self.installed = installed
        self.skipped = skipped
        self.failed = failed
    }
}

/// A template that was skipped during installation.
package struct SkippedTemplate: Sendable, Equatable {
    /// The name of the skipped template.
    package let name: String

    /// The reason why the template was skipped.
    package let reason: SkipReason

    package init(name: String, reason: SkipReason) {
        self.name = name
        self.reason = reason
    }
}

/// Reasons why a template might be skipped during installation.
package enum SkipReason: Sendable, Equatable {
    /// The template already exists at the destination.
    case alreadyExists

    /// The template was excluded by the filter.
    case excludedByFilter
}

/// A template that failed to install.
package struct FailedTemplate: Sendable {
    /// The name of the failed template.
    package let name: String

    /// The error that occurred during installation.
    package let error: any Error

    package init(name: String, error: any Error) {
        self.name = name
        self.error = error
    }
}
