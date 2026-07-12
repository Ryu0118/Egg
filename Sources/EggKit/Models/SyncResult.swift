import Foundation

/// The result of `egg template sync` / `egg template update` across all
/// processed manifest scopes.
public struct SyncResult: Sendable {
    public let dryRun: Bool
    public let scopes: [SyncScopeResult]

    public init(dryRun: Bool, scopes: [SyncScopeResult]) {
        self.dryRun = dryRun
        self.scopes = scopes
    }

    /// Whether any entry in any scope failed. Drives the nonzero exit code
    /// (successful entries are still installed and locked).
    public var hasFailures: Bool {
        scopes.contains { scope in
            scope.entries.contains { !$0.failed.isEmpty }
        }
    }
}

/// The result of syncing one manifest scope (global or project).
public struct SyncScopeResult: Sendable {
    public let scope: String
    public let manifestPath: String
    public let lockfilePath: String
    public let entries: [SyncEntryResult]
    /// Whether the lockfile was (re)written for this scope.
    public let lockfileWritten: Bool

    public init(
        scope: String,
        manifestPath: String,
        lockfilePath: String,
        entries: [SyncEntryResult],
        lockfileWritten: Bool,
    ) {
        self.scope = scope
        self.manifestPath = manifestPath
        self.lockfilePath = lockfilePath
        self.entries = entries
        self.lockfileWritten = lockfileWritten
    }
}

/// The result of processing one manifest entry.
public struct SyncEntryResult: Sendable {
    /// The normalized URL for git entries (the lockfile key), or the
    /// declared path for local entries.
    public let url: String
    /// The version requirement as written (e.g. "from: 1.0.0"), `nil` for
    /// local entries.
    public let requirement: String?
    public let resolvedVersion: String?
    public let resolvedRevision: String?
    /// Whether the resolution was reused from the lockfile.
    public let reusedLock: Bool
    public let installed: [String]
    public let skipped: [SkippedTemplate]
    public let failed: [SyncFailure]

    public init(
        url: String,
        requirement: String?,
        resolvedVersion: String? = nil,
        resolvedRevision: String? = nil,
        reusedLock: Bool = false,
        installed: [String] = [],
        skipped: [SkippedTemplate] = [],
        failed: [SyncFailure] = [],
    ) {
        self.url = url
        self.requirement = requirement
        self.resolvedVersion = resolvedVersion
        self.resolvedRevision = resolvedRevision
        self.reusedLock = reusedLock
        self.installed = installed
        self.skipped = skipped
        self.failed = failed
    }
}

/// A failure while processing a manifest entry.
public struct SyncFailure: Sendable {
    /// The template name for per-template failures (e.g. a name collision),
    /// `nil` for entry-level failures (resolution, clone, auth).
    public let name: String?
    public let error: any Error

    public init(name: String?, error: any Error) {
        self.name = name
        self.error = error
    }
}

public extension SyncResult {
    /// JSON-encodable projection shared by the CLI `--json` path and the
    /// MCP tools, mirroring ``InstallResult/Encoded``.
    struct Encoded: Codable, Sendable, Equatable {
        public let dryRun: Bool
        public let scopes: [Scope]

        public struct Scope: Codable, Sendable, Equatable {
            public let scope: String
            public let manifestPath: String
            public let lockfilePath: String
            public let entries: [Entry]
            public let lockfileWritten: Bool
        }

        public struct Entry: Codable, Sendable, Equatable {
            public let url: String
            public let requirement: String?
            public let resolvedVersion: String?
            public let resolvedRevision: String?
            public let reusedLock: Bool
            public let installed: [String]
            public let skipped: [InstallResult.Encoded.SkippedItem]
            public let failed: [Failure]
        }

        public struct Failure: Codable, Sendable, Equatable {
            public let name: String?
            public let error: String
        }
    }

    var encoded: Encoded {
        Encoded(
            dryRun: dryRun,
            scopes: scopes.map { scope in
                Encoded.Scope(
                    scope: scope.scope,
                    manifestPath: scope.manifestPath,
                    lockfilePath: scope.lockfilePath,
                    entries: scope.entries.map { entry in
                        Encoded.Entry(
                            url: entry.url,
                            requirement: entry.requirement,
                            resolvedVersion: entry.resolvedVersion,
                            resolvedRevision: entry.resolvedRevision,
                            reusedLock: entry.reusedLock,
                            installed: entry.installed,
                            skipped: entry.skipped.map { .init(name: $0.name, reason: $0.reason.jsonValue) },
                            failed: entry.failed.map { .init(name: $0.name, error: $0.error.localizedDescription) },
                        )
                    },
                    lockfileWritten: scope.lockfileWritten,
                )
            },
        )
    }
}
