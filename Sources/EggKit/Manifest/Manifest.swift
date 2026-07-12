import Foundation

/// A parsed eggs.yml template manifest.
///
/// Declares external template sources to be resolved and installed by
/// `egg template sync` / `egg template update`.
package struct Manifest: Equatable {
    package let templates: [ManifestEntry]

    package init(templates: [ManifestEntry]) {
        self.templates = templates
    }

    /// Returns a new manifest with `entry` merged in: replaces any existing
    /// entry sharing the same `lockKey`, or appends when none matches.
    ///
    /// The requirement always replaces; the filter only replaces when
    /// `entry.filter` is non-`.none`, so a filter-less re-install (e.g. a
    /// plain `egg template install --global <url>` re-run) doesn't silently
    /// widen an existing entry's `only:`/`exclude:` scope back open.
    package func upserting(_ entry: ManifestEntry) -> Manifest {
        guard let key = entry.source.lockKey,
              let index = templates.firstIndex(where: { $0.source.lockKey == key })
        else {
            return Manifest(templates: templates + [entry])
        }

        var merged = templates
        let existing = merged[index]
        merged[index] = ManifestEntry(
            declaredURL: entry.declaredURL,
            source: entry.source,
            filter: entry.filter == .none ? existing.filter : entry.filter,
        )
        return Manifest(templates: merged)
    }
}

/// One declared template source in eggs.yml.
package struct ManifestEntry: Equatable {
    /// The `url` value exactly as written in eggs.yml (before shorthand
    /// expansion), used in user-facing messages.
    package let declaredURL: String
    package let source: ManifestEntrySource
    package let filter: TemplateFilter

    package init(declaredURL: String, source: ManifestEntrySource, filter: TemplateFilter) {
        self.declaredURL = declaredURL
        self.source = source
        self.filter = filter
    }
}

/// Where a manifest entry's templates come from.
package enum ManifestEntrySource: Equatable {
    /// A remote Git repository with a version requirement.
    case git(url: GitURL, requirement: VersionRequirement)
    /// A local directory, installed as-is and never recorded in the
    /// lockfile (unpinnable, mirrors SwiftPM local packages).
    case local(path: String)

    /// The canonical URL string used as the lockfile lookup key.
    /// `nil` for local paths, which are never locked.
    package var lockKey: String? {
        switch self {
        case let .git(url, _):
            url.original
        case .local:
            nil
        }
    }
}

/// How a Git manifest entry pins its version. Exactly one per entry.
package enum VersionRequirement: Equatable, CustomStringConvertible {
    /// SwiftPM `.upToNextMajor` semantics: `[version, (major + 1).0.0)`.
    case from(SemanticVersion)
    /// A single version, matched against tags by parsed-version equality
    /// (so `exact: "1.2.0"` matches both `1.2.0` and `v1.2.0`).
    case exact(SemanticVersion)
    /// Follow a branch. Floating by design; `sync` installs the locked
    /// revision, `update` moves to the branch tip.
    case branch(String)
    /// A fixed commit SHA. Trivially locked.
    case revision(String)

    package var description: String {
        switch self {
        case let .from(version):
            "from: \(version)"
        case let .exact(version):
            "exact: \(version)"
        case let .branch(name):
            "branch: \(name)"
        case let .revision(sha):
            "revision: \(sha)"
        }
    }
}

// MARK: - Raw YAML decoding/encoding

/// The eggs.yml document as decoded from YAML, before entry validation.
struct RawManifest: Codable {
    let templates: [RawManifestEntry]

    init(templates: [RawManifestEntry]) {
        self.templates = templates
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        templates = try container.decodeIfPresent([RawManifestEntry].self, forKey: .templates) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case templates
    }
}

/// One raw eggs.yml entry; validated and converted by ``ManifestEntry/make(from:)``.
struct RawManifestEntry: Codable {
    let url: String
    let from: String?
    let exact: String?
    let branch: String?
    let revision: String?
    let only: [String]?
    let exclude: [String]?
}

extension RawManifest {
    /// Converts a typed ``Manifest`` back into its raw YAML shape, sorted by
    /// `declaredURL` so repeated writes produce stable diffs.
    package init(_ manifest: Manifest) {
        templates = manifest.templates
            .sorted { $0.declaredURL < $1.declaredURL }
            .map(RawManifestEntry.init)
    }
}

extension RawManifestEntry {
    init(_ entry: ManifestEntry) {
        let requirement: VersionRequirement? = if case let .git(_, requirement) = entry.source { requirement } else { nil }

        switch requirement {
        case let .from(version):
            self.init(url: entry.declaredURL, from: version.description, exact: nil, branch: nil, revision: nil, filter: entry.filter)
        case let .exact(version):
            self.init(url: entry.declaredURL, from: nil, exact: version.description, branch: nil, revision: nil, filter: entry.filter)
        case let .branch(name):
            self.init(url: entry.declaredURL, from: nil, exact: nil, branch: name, revision: nil, filter: entry.filter)
        case let .revision(sha):
            self.init(url: entry.declaredURL, from: nil, exact: nil, branch: nil, revision: sha, filter: entry.filter)
        case nil:
            self.init(url: entry.declaredURL, from: nil, exact: nil, branch: nil, revision: nil, filter: entry.filter)
        }
    }

    private init(url: String, from: String?, exact: String?, branch: String?, revision: String?, filter: TemplateFilter) {
        let (only, exclude): ([String]?, [String]?) = switch filter {
        case .none: (nil, nil)
        case let .include(names): (names, nil)
        case let .exclude(names): (nil, names)
        }
        self.init(url: url, from: from, exact: exact, branch: branch, revision: revision, only: only, exclude: exclude)
    }
}

extension ManifestEntry {
    /// GitHub shorthand: `owner/repo` with no scheme and no path prefix.
    private static let shorthandPattern = #"^[\w.\-]+/[\w.\-]+$"#

    /// Validates a raw entry and converts it into a typed ``ManifestEntry``.
    ///
    /// - Throws: `ManifestLoaderError.invalidEntry` when the entry violates
    ///   the manifest rules (version-key count, filter exclusivity, semver
    ///   syntax, URL syntax).
    static func make(from raw: RawManifestEntry) throws -> ManifestEntry {
        let filter = try makeFilter(from: raw)
        let source = try makeSource(from: raw)
        return ManifestEntry(declaredURL: raw.url, source: source, filter: filter)
    }

    private static func makeFilter(from raw: RawManifestEntry) throws -> TemplateFilter {
        switch (raw.only, raw.exclude) {
        case (.some, .some):
            throw ManifestLoaderError.invalidEntry(
                url: raw.url,
                reason: "'only' and 'exclude' are mutually exclusive",
            )
        case let (.some(only), .none):
            return .include(only)
        case let (.none, .some(exclude)):
            return .exclude(exclude)
        case (.none, .none):
            return .none
        }
    }

    private static func makeSource(from raw: RawManifestEntry) throws -> ManifestEntrySource {
        let trimmedURL = raw.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else {
            throw ManifestLoaderError.invalidEntry(url: raw.url, reason: "'url' must not be empty")
        }

        if let gitURL = parseGitURL(trimmedURL) {
            return try .git(url: gitURL, requirement: makeRequirement(from: raw))
        }

        guard versionKeyCount(of: raw) == 0 else {
            throw ManifestLoaderError.invalidEntry(
                url: raw.url,
                reason: "version specifiers are not allowed for local paths",
            )
        }
        return .local(path: trimmedURL)
    }

    private static func versionKeyCount(of raw: RawManifestEntry) -> Int {
        [raw.from, raw.exact, raw.branch, raw.revision].compactMap(\.self).count
    }

    private static func parseGitURL(_ urlString: String) -> GitURL? {
        if urlString.range(of: shorthandPattern, options: .regularExpression) != nil {
            // "." and ".." segments are relative paths (e.g. "../shared"),
            // not GitHub owner/repo names.
            let segments = urlString.split(separator: "/")
            guard !segments.contains("."), !segments.contains("..") else {
                return nil
            }
            let expanded = "https://github.com/\(urlString).git"
            return GitURLParser().parse(expanded)
        }
        return GitURLParser().parse(urlString)
    }

    private static func makeRequirement(from raw: RawManifestEntry) throws -> VersionRequirement {
        let specifiers: [(key: String, value: String)] = [
            ("from", raw.from),
            ("exact", raw.exact),
            ("branch", raw.branch),
            ("revision", raw.revision),
        ].compactMap { key, value in
            value.map { (key, $0) }
        }

        guard specifiers.count == 1, let specifier = specifiers.first else {
            throw ManifestLoaderError.invalidEntry(
                url: raw.url,
                reason: "specify exactly one of 'from', 'exact', 'branch', 'revision' (found \(specifiers.count))",
            )
        }

        switch specifier.key {
        case "from":
            return try .from(parseVersion(specifier.value, key: "from", url: raw.url))
        case "exact":
            return try .exact(parseVersion(specifier.value, key: "exact", url: raw.url))
        case "branch":
            guard !specifier.value.isEmpty else {
                throw ManifestLoaderError.invalidEntry(url: raw.url, reason: "'branch' must not be empty")
            }
            return .branch(specifier.value)
        default:
            guard !specifier.value.isEmpty else {
                throw ManifestLoaderError.invalidEntry(url: raw.url, reason: "'revision' must not be empty")
            }
            return .revision(specifier.value)
        }
    }

    private static func parseVersion(_ string: String, key: String, url: String) throws -> SemanticVersion {
        guard let version = SemanticVersion(string) else {
            throw ManifestLoaderError.invalidEntry(
                url: url,
                reason: "invalid semantic version '\(string)' for '\(key)'",
            )
        }
        return version
    }
}
