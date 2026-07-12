import Foundation

/// What a manifest entry resolved to, ready to install and to record in
/// the lockfile.
package struct Resolution: Equatable {
    /// The commit SHA to install from.
    package let revision: String
    /// The tag that was selected, when the requirement is version-based.
    package let tag: String?
    /// The resolved semantic version, when the requirement is version-based.
    package let version: SemanticVersion?
    /// The followed branch, when the requirement is a branch.
    package let branch: String?
    /// Whether this resolution was taken from the lockfile without
    /// consulting the remote.
    package let reusedLock: Bool

    package init(
        revision: String,
        tag: String? = nil,
        version: SemanticVersion? = nil,
        branch: String? = nil,
        reusedLock: Bool = false,
    ) {
        self.revision = revision
        self.tag = tag
        self.version = version
        self.branch = branch
        self.reusedLock = reusedLock
    }
}

/// Pure resolution logic: no I/O. The runner feeds it remote tags from
/// ``GitTagLister`` and locked state from ``LockfileStore``.
package enum VersionResolver {
    /// Package.resolved semantics for `sync`: returns the locked resolution
    /// when it still satisfies the CURRENT manifest requirement, else `nil`
    /// (caller must resolve fresh). `update` never calls this.
    package static func reusableResolution(
        for requirement: VersionRequirement,
        locked: LockedResolution?,
    ) -> Resolution? {
        guard let locked else {
            return nil
        }

        switch requirement {
        case let .from(lowerBound):
            guard let lockedVersion = locked.semanticVersion,
                  lockedVersion.satisfies(upToNextMajorFrom: lowerBound)
            else {
                return nil
            }
            return Resolution(
                revision: locked.revision,
                tag: locked.tag,
                version: lockedVersion,
                reusedLock: true,
            )

        case let .exact(version):
            guard locked.semanticVersion == version else {
                return nil
            }
            return Resolution(
                revision: locked.revision,
                tag: locked.tag,
                version: version,
                reusedLock: true,
            )

        case let .branch(name):
            guard locked.branch == name else {
                return nil
            }
            return Resolution(revision: locked.revision, branch: name, reusedLock: true)

        case let .revision(sha):
            guard locked.revision == sha else {
                return nil
            }
            return Resolution(revision: sha, reusedLock: true)
        }
    }

    /// Resolves a `from`/`exact` requirement against the tags advertised by
    /// the remote. Non-semver tags are ignored; when the same version exists
    /// with and without a `v` prefix, the non-`v` tag wins (SwiftPM behavior).
    ///
    /// - Throws: `ResolutionError.noMatchingVersion` when nothing satisfies
    ///   the requirement, naming the highest semver tag the remote has.
    package static func resolve(
        requirement: VersionRequirement,
        tags: [GitRemoteTag],
        url: String,
    ) throws -> Resolution {
        let candidates = semverCandidates(from: tags)
        let highestAvailable = candidates.values.map(\.version).max()

        let selected: (version: SemanticVersion, tag: GitRemoteTag)?
        switch requirement {
        case let .from(lowerBound):
            selected = candidates.values
                .filter { $0.version.satisfies(upToNextMajorFrom: lowerBound) }
                .max { $0.version < $1.version }
                .map { ($0.version, $0.tag) }

        case let .exact(version):
            selected = candidates[version].map { ($0.version, $0.tag) }

        case .branch, .revision:
            preconditionFailure("branch/revision requirements are not tag-resolved")
        }

        guard let selected else {
            throw ResolutionError.noMatchingVersion(
                url: url,
                requirement: requirement.description,
                highestAvailable: highestAvailable?.description,
            )
        }

        return Resolution(
            revision: selected.tag.revision,
            tag: selected.tag.name,
            version: selected.version,
        )
    }

    /// Builds the candidate set: one tag per parsed version, preferring the
    /// non-`v`-prefixed tag when both spellings exist.
    private static func semverCandidates(
        from tags: [GitRemoteTag],
    ) -> [SemanticVersion: (version: SemanticVersion, tag: GitRemoteTag, hadVPrefix: Bool)] {
        var candidates: [SemanticVersion: (version: SemanticVersion, tag: GitRemoteTag, hadVPrefix: Bool)] = [:]
        for tag in tags {
            guard let parsed = SemanticVersion.parse(tag: tag.name) else {
                continue
            }
            if let existing = candidates[parsed.version] {
                if existing.hadVPrefix, !parsed.hadVPrefix {
                    candidates[parsed.version] = (parsed.version, tag, parsed.hadVPrefix)
                }
            } else {
                candidates[parsed.version] = (parsed.version, tag, parsed.hadVPrefix)
            }
        }
        return candidates
    }
}

/// Errors that can occur while resolving a manifest entry's version.
package enum ResolutionError: Error, LocalizedError, Equatable {
    /// No tag satisfies the requirement. `highestAvailable` is the highest
    /// semver tag the remote advertised, or `nil` when it has none.
    case noMatchingVersion(url: String, requirement: String, highestAvailable: String?)
    /// The remote does not advertise the requested branch.
    case branchNotFound(url: String, branch: String)

    package var errorDescription: String? {
        switch self {
        case let .noMatchingVersion(url, requirement, highestAvailable):
            if let highestAvailable {
                "no version satisfying '\(requirement)' for \(url) (highest available: \(highestAvailable))"
            } else {
                "no version satisfying '\(requirement)' for \(url) (no semver tags found)"
            }
        case let .branchNotFound(url, branch):
            "branch '\(branch)' not found in \(url)"
        }
    }
}
