@testable import EggKit
import FileManagerProtocol
import Foundation
import Testing

struct ManifestWriterTests {
    private let fileManager: some FileManagerProtocol = FileManager.default

    @Test("round-trips through ManifestLoader.load")
    func roundTrip() throws {
        let manifest = Manifest(templates: [
            ManifestEntry(
                declaredURL: "https://github.com/a/from-repo.git",
                source: .git(
                    url: GitURL(original: "https://github.com/a/from-repo.git", normalized: "https://github.com/a/from-repo.git"),
                    requirement: .from(SemanticVersion(major: 1, minor: 0, patch: 0)),
                ),
                filter: .none,
            ),
            ManifestEntry(
                declaredURL: "https://github.com/b/exact-repo.git",
                source: .git(
                    url: GitURL(original: "https://github.com/b/exact-repo.git", normalized: "https://github.com/b/exact-repo.git"),
                    requirement: .exact(SemanticVersion(major: 1, minor: 2, patch: 0)),
                ),
                filter: .include(["SwiftCLI"]),
            ),
            ManifestEntry(
                declaredURL: "git@github.com:c/branch-repo.git",
                source: .git(
                    url: GitURL(original: "git@github.com:c/branch-repo.git", normalized: "git@github.com:c/branch-repo.git"),
                    requirement: .branch("main"),
                ),
                filter: .exclude(["Deprecated"]),
            ),
            ManifestEntry(
                declaredURL: "./local-templates",
                source: .local(path: "./local-templates"),
                filter: .none,
            ),
        ])

        let root = try fileManager.makeTemporaryDirectory(prefix: "ManifestWriterTests")
        defer { try? fileManager.removeItem(at: root) }
        let manifestPath = root.appending(path: "eggs.yml")

        try ManifestWriter(fileManager: fileManager).save(manifest, to: manifestPath)
        let loaded = try ManifestLoader(fileManager: fileManager).load(manifestPath: manifestPath)

        #expect(loaded.templates.count == manifest.templates.count)
        #expect(loaded.templates.sorted { $0.declaredURL < $1.declaredURL } == manifest.templates.sorted { $0.declaredURL < $1.declaredURL })
    }

    @Test("writes are stable: entries sorted by declaredURL regardless of input order")
    func stableOutput() throws {
        let first = ManifestEntry(
            declaredURL: "https://github.com/a/repo.git",
            source: .git(
                url: GitURL(original: "https://github.com/a/repo.git", normalized: "https://github.com/a/repo.git"),
                requirement: .branch("main"),
            ),
            filter: .none,
        )
        let second = ManifestEntry(
            declaredURL: "https://github.com/b/repo.git",
            source: .git(
                url: GitURL(original: "https://github.com/b/repo.git", normalized: "https://github.com/b/repo.git"),
                requirement: .branch("main"),
            ),
            filter: .none,
        )

        let root = try fileManager.makeTemporaryDirectory(prefix: "ManifestWriterTests")
        defer { try? fileManager.removeItem(at: root) }
        let writer = ManifestWriter(fileManager: fileManager)

        let forwardPath = root.appending(path: "forward.yml")
        let reversedPath = root.appending(path: "reversed.yml")
        try writer.save(Manifest(templates: [first, second]), to: forwardPath)
        try writer.save(Manifest(templates: [second, first]), to: reversedPath)

        let forward = try fileManager.readFile(at: forwardPath)
        let reversed = try fileManager.readFile(at: reversedPath)
        #expect(forward == reversed)
    }

    @Test("creates the parent directory when it doesn't exist yet")
    func createsParentDirectory() throws {
        let root = try fileManager.makeTemporaryDirectory(prefix: "ManifestWriterTests")
        defer { try? fileManager.removeItem(at: root) }
        let nestedManifestPath = root.appending(path: "egg", directoryHint: .isDirectory).appending(path: "eggs.yml")

        try ManifestWriter(fileManager: fileManager).save(Manifest(templates: []), to: nestedManifestPath)

        #expect(fileManager.exists(nestedManifestPath))
    }

    @Test("Manifest.upserting replaces an existing entry sharing the same lock key rather than duplicating it")
    func upsertReplaces() {
        let url = GitURL(original: "https://github.com/a/repo.git", normalized: "https://github.com/a/repo.git")
        let original = Manifest(templates: [
            ManifestEntry(
                declaredURL: "https://github.com/a/repo.git",
                source: .git(url: url, requirement: .branch("main")),
                filter: .include(["SwiftCLI"]),
            ),
        ])

        let replacement = ManifestEntry(
            declaredURL: "https://github.com/a/repo.git",
            source: .git(url: url, requirement: .exact(SemanticVersion(major: 1, minor: 0, patch: 0))),
            filter: .none,
        )
        let merged = original.upserting(replacement)

        #expect(merged.templates.count == 1)
        #expect(merged.templates[0].source == .git(url: url, requirement: .exact(SemanticVersion(major: 1, minor: 0, patch: 0))))
        // Filter-less re-install must not silently widen an existing scoped filter.
        #expect(merged.templates[0].filter == .include(["SwiftCLI"]))
    }

    @Test("Manifest.upserting overwrites the filter when the incoming one is non-none")
    func upsertReplacesFilterWhenExplicit() {
        let url = GitURL(original: "https://github.com/a/repo.git", normalized: "https://github.com/a/repo.git")
        let original = Manifest(templates: [
            ManifestEntry(
                declaredURL: "https://github.com/a/repo.git",
                source: .git(url: url, requirement: .branch("main")),
                filter: .include(["SwiftCLI"]),
            ),
        ])

        let replacement = ManifestEntry(
            declaredURL: "https://github.com/a/repo.git",
            source: .git(url: url, requirement: .branch("main")),
            filter: .exclude(["Deprecated"]),
        )
        let merged = original.upserting(replacement)

        #expect(merged.templates[0].filter == .exclude(["Deprecated"]))
    }

    @Test("Manifest.upserting appends when no entry shares the lock key")
    func upsertAppends() {
        let existing = ManifestEntry(
            declaredURL: "https://github.com/a/repo.git",
            source: .git(
                url: GitURL(original: "https://github.com/a/repo.git", normalized: "https://github.com/a/repo.git"),
                requirement: .branch("main"),
            ),
            filter: .none,
        )
        let new = ManifestEntry(
            declaredURL: "https://github.com/b/repo.git",
            source: .git(
                url: GitURL(original: "https://github.com/b/repo.git", normalized: "https://github.com/b/repo.git"),
                requirement: .branch("main"),
            ),
            filter: .none,
        )

        let merged = Manifest(templates: [existing]).upserting(new)
        #expect(merged.templates.count == 2)
    }

    @Test("Lockfile.upserting replaces an existing entry sharing the same url rather than duplicating it")
    func lockfileUpsertReplaces() {
        let original = Lockfile(templates: [
            LockedTemplate(
                url: "https://github.com/a/repo.git",
                requirement: LockedRequirement(.branch("main")),
                resolved: LockedResolution(branch: "main", revision: String(repeating: "a", count: 40)),
            ),
        ])

        let replacement = LockedTemplate(
            url: "https://github.com/a/repo.git",
            requirement: LockedRequirement(.exact(SemanticVersion(major: 1, minor: 0, patch: 0))),
            resolved: LockedResolution(version: "1.0.0", tag: "1.0.0", revision: String(repeating: "b", count: 40)),
        )
        let merged = original.upserting(replacement)

        #expect(merged.templates.count == 1)
        #expect(merged.templates[0].resolved.revision == String(repeating: "b", count: 40))
    }
}
