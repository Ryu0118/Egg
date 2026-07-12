import Foundation

/// The egg-lock.yml document: the resolved state of an egg.yml manifest.
///
/// Sits next to its manifest and is regenerated from the manifest on every
/// sync/update write; entries whose url left the manifest drop out. Local
/// path entries are never recorded (unpinnable).
package struct Lockfile: Codable, Equatable {
    /// Lockfile schema version. Currently always 1.
    package static let currentVersion = 1

    package let version: Int
    package let templates: [LockedTemplate]

    package init(version: Int = Lockfile.currentVersion, templates: [LockedTemplate]) {
        self.version = version
        self.templates = templates
    }

    /// Looks up the locked entry for a normalized manifest URL (the
    /// ``ManifestEntrySource/lockKey``).
    package func entry(forURL url: String) -> LockedTemplate? {
        templates.first { $0.url == url }
    }
}

/// One resolved manifest entry in egg-lock.yml.
package struct LockedTemplate: Codable, Equatable {
    /// The normalized (post-shorthand) Git URL. Lookup key.
    package let url: String
    /// The manifest requirement at the time of resolution. Recorded for
    /// debuggability only — reuse decisions always read the current
    /// manifest, never this echo.
    package let requirement: LockedRequirement
    package let resolved: LockedResolution

    package init(url: String, requirement: LockedRequirement, resolved: LockedResolution) {
        self.url = url
        self.requirement = requirement
        self.resolved = resolved
    }
}

/// A ``VersionRequirement`` in its YAML shape: exactly one key set.
package struct LockedRequirement: Codable, Equatable {
    package let from: String?
    package let exact: String?
    package let branch: String?
    package let revision: String?

    package init(_ requirement: VersionRequirement) {
        switch requirement {
        case let .from(version):
            self.init(from: version.description)
        case let .exact(version):
            self.init(exact: version.description)
        case let .branch(name):
            self.init(branch: name)
        case let .revision(sha):
            self.init(revision: sha)
        }
    }

    private init(from: String? = nil, exact: String? = nil, branch: String? = nil, revision: String? = nil) {
        self.from = from
        self.exact = exact
        self.branch = branch
        self.revision = revision
    }
}

/// What a manifest entry resolved to.
package struct LockedResolution: Codable, Equatable {
    /// The canonical resolved version (no `v` prefix). `nil` for
    /// branch/revision requirements.
    package let version: String?
    /// The actual tag string, which may carry a `v` prefix. `nil` for
    /// branch/revision requirements.
    package let tag: String?
    /// The followed branch. `nil` unless the requirement is a branch.
    package let branch: String?
    /// The commit SHA to install from. Always present; peeled for
    /// annotated tags.
    package let revision: String

    package init(version: String? = nil, tag: String? = nil, branch: String? = nil, revision: String) {
        self.version = version
        self.tag = tag
        self.branch = branch
        self.revision = revision
    }

    /// The resolved version parsed back into a ``SemanticVersion``, when
    /// the lock recorded one.
    package var semanticVersion: SemanticVersion? {
        version.flatMap(SemanticVersion.init)
    }
}
