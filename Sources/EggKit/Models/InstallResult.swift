import Foundation

/// The result of installing templates from a repository.
public struct InstallResult: Sendable {
    /// Names of templates that were successfully installed.
    public let installed: [String]

    /// Templates that were skipped during installation.
    public let skipped: [SkippedTemplate]

    /// Templates that failed to install.
    public let failed: [FailedTemplate]

    /// The eggs.yml manifest path this install registered itself into, when
    /// it was a `--global` git-source install with at least one template
    /// installed. `nil` for project/local-path installs, or when
    /// registration was attempted but failed (a warning is emitted instead
    /// of failing the overall install).
    public let manifestUpdated: String?

    public init(
        installed: [String],
        skipped: [SkippedTemplate],
        failed: [FailedTemplate],
        manifestUpdated: String? = nil,
    ) {
        self.installed = installed
        self.skipped = skipped
        self.failed = failed
        self.manifestUpdated = manifestUpdated
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

public extension InstallResult {
    /// JSON-encodable projection of the result, shared by every frontend
    /// (CLI `--json` and the MCP tool): `any Error` values flatten to their
    /// localized descriptions and skip reasons to stable snake_case strings.
    struct Encoded: Codable, Sendable, Equatable {
        public let installed: [String]
        public let skipped: [SkippedItem]
        public let failed: [FailedItem]
        public let manifestUpdated: String?

        public struct SkippedItem: Codable, Sendable, Equatable {
            public let name: String
            public let reason: String
        }

        public struct FailedItem: Codable, Sendable, Equatable {
            public let name: String
            public let error: String
        }
    }

    var encoded: Encoded {
        Encoded(
            installed: installed,
            skipped: skipped.map { .init(name: $0.name, reason: $0.reason.jsonValue) },
            failed: failed.map { .init(name: $0.name, error: $0.error.localizedDescription) },
            manifestUpdated: manifestUpdated,
        )
    }
}

public extension SkipReason {
    /// Stable identifier used in JSON output.
    var jsonValue: String {
        switch self {
        case .alreadyExists:
            "already_exists"
        case .excludedByFilter:
            "excluded_by_filter"
        }
    }
}
