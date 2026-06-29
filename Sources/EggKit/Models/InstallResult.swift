import Foundation

/// The result of installing templates from a repository.
public struct InstallResult: Sendable {
    /// Names of templates that were successfully installed.
    public let installed: [String]

    /// Templates that were skipped during installation.
    public let skipped: [SkippedTemplate]

    /// Templates that failed to install.
    public let failed: [FailedTemplate]

    public init(
        installed: [String],
        skipped: [SkippedTemplate],
        failed: [FailedTemplate],
    ) {
        self.installed = installed
        self.skipped = skipped
        self.failed = failed
    }
}

/// A template that was skipped during installation.
public struct SkippedTemplate: Sendable, Equatable {
    /// The name of the skipped template.
    public let name: String

    /// The reason why the template was skipped.
    public let reason: SkipReason

    public init(name: String, reason: SkipReason) {
        self.name = name
        self.reason = reason
    }
}

/// Reasons why a template might be skipped during installation.
public enum SkipReason: Sendable, Equatable {
    /// The template already exists at the destination.
    case alreadyExists

    /// The template was excluded by the filter.
    case excludedByFilter
}

/// A template that failed to install.
public struct FailedTemplate: Sendable {
    /// The name of the failed template.
    public let name: String

    /// The error that occurred during installation.
    public let error: any Error

    public init(name: String, error: any Error) {
        self.name = name
        self.error = error
    }
}
