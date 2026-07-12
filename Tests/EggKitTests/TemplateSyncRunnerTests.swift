@testable import EggKit
import FileManagerProtocol
import Foundation
import Testing

struct TemplateSyncRunnerTests {
    private static let tagSHA = String(repeating: "a", count: 40)
    private static let newerTagSHA = String(repeating: "b", count: 40)
    private static let branchTipSHA = String(repeating: "c", count: 40)
    private static let movedTipSHA = String(repeating: "d", count: 40)
    private static let repoURL = "https://github.com/owner/repo.git"

    // MARK: - First sync

    @Test("first sync resolves from tags, installs, and writes the lockfile")
    func firstSync() async throws {
        let env = try TestEnvironment()
        defer { env.tearDown() }
        try env.seedTemplate(named: "MyTemplate")
        try env.writeManifest("""
        templates:
          - url: \(Self.repoURL)
            from: "1.0.0"
        """)

        let tagLister = MockGitTagLister(tags: [
            GitRemoteTag(name: "1.0.0", objectSHA: String(repeating: "e", count: 40)),
            GitRemoteTag(name: "v1.1.0", objectSHA: String(repeating: "f", count: 40), peeledSHA: Self.tagSHA),
            GitRemoteTag(name: "2.0.0-beta.1", objectSHA: String(repeating: "0", count: 40)),
        ])
        let cloner = MockGitCloner(seedDirectory: env.seedDirectory, fileManager: env.fileManager)

        let result = try await env.runner(mode: .sync, tagLister: tagLister, cloner: cloner).run()

        #expect(!result.hasFailures)
        let entry = try #require(result.scopes.first?.entries.first)
        #expect(entry.resolvedVersion == "1.1.0")
        #expect(entry.resolvedRevision == Self.tagSHA, "annotated tag installs from the peeled SHA")
        #expect(!entry.reusedLock)
        #expect(entry.installed == ["MyTemplate"])
        #expect(cloner.requestedRefs == [.revision(Self.tagSHA)])
        #expect(env.installedTemplateExists("MyTemplate"))

        let lockfile = try #require(try LockfileStore(fileManager: env.fileManager).load(lockfilePath: env.lockfileURL))
        let locked = try #require(lockfile.entry(forURL: Self.repoURL))
        #expect(locked.resolved.version == "1.1.0")
        #expect(locked.resolved.tag == "v1.1.0")
        #expect(locked.resolved.revision == Self.tagSHA)
        #expect(locked.requirement == LockedRequirement(.from(SemanticVersion(major: 1, minor: 0, patch: 0))))
    }

    // MARK: - Lock reuse

    @Test("re-sync reuses the lock without touching the remote for tags")
    func resyncReusesLock() async throws {
        let env = try TestEnvironment()
        defer { env.tearDown() }
        try env.seedTemplate(named: "MyTemplate")
        try env.writeManifest("""
        templates:
          - url: \(Self.repoURL)
            from: "1.0.0"
        """)
        try env.writeLock(version: "1.1.0", tag: "v1.1.0", revision: Self.tagSHA)

        // Listing tags would mean the lock was ignored.
        let tagLister = MockGitTagLister(failOnListTags: true)
        let cloner = MockGitCloner(seedDirectory: env.seedDirectory, fileManager: env.fileManager)

        let result = try await env.runner(mode: .sync, tagLister: tagLister, cloner: cloner).run()

        let entry = try #require(result.scopes.first?.entries.first)
        #expect(entry.reusedLock)
        #expect(entry.resolvedVersion == "1.1.0")
        #expect(cloner.requestedRefs == [.revision(Self.tagSHA)])
    }

    @Test("bumping the constraint past the locked version re-resolves")
    func constraintBumpReresolves() async throws {
        let env = try TestEnvironment()
        defer { env.tearDown() }
        try env.seedTemplate(named: "MyTemplate")
        try env.writeManifest("""
        templates:
          - url: \(Self.repoURL)
            from: "2.0.0"
        """)
        try env.writeLock(version: "1.1.0", tag: "v1.1.0", revision: Self.tagSHA)

        let tagLister = MockGitTagLister(tags: [
            GitRemoteTag(name: "2.1.0", objectSHA: Self.newerTagSHA),
        ])
        let cloner = MockGitCloner(seedDirectory: env.seedDirectory, fileManager: env.fileManager)

        let result = try await env.runner(mode: .sync, tagLister: tagLister, cloner: cloner).run()

        let entry = try #require(result.scopes.first?.entries.first)
        #expect(!entry.reusedLock)
        #expect(entry.resolvedVersion == "2.1.0")
        #expect(cloner.requestedRefs == [.revision(Self.newerTagSHA)])
    }

    @Test("update ignores the lock and re-resolves to the latest eligible")
    func updateReresolves() async throws {
        let env = try TestEnvironment()
        defer { env.tearDown() }
        try env.seedTemplate(named: "MyTemplate")
        try env.writeManifest("""
        templates:
          - url: \(Self.repoURL)
            from: "1.0.0"
        """)
        try env.writeLock(version: "1.1.0", tag: "v1.1.0", revision: Self.tagSHA)

        let tagLister = MockGitTagLister(tags: [
            GitRemoteTag(name: "v1.1.0", objectSHA: Self.tagSHA),
            GitRemoteTag(name: "1.4.0", objectSHA: Self.newerTagSHA),
        ])
        let cloner = MockGitCloner(seedDirectory: env.seedDirectory, fileManager: env.fileManager)

        let result = try await env.runner(mode: .update, tagLister: tagLister, cloner: cloner).run()

        let entry = try #require(result.scopes.first?.entries.first)
        #expect(entry.resolvedVersion == "1.4.0")
        #expect(!entry.reusedLock)

        let lockfile = try #require(try LockfileStore(fileManager: env.fileManager).load(lockfilePath: env.lockfileURL))
        #expect(lockfile.entry(forURL: Self.repoURL)?.resolved.version == "1.4.0")
    }

    // MARK: - Branch entries

    @Test(
        "branch sync pins the locked SHA even when the tip moved; update follows the tip",
        arguments: [
            BranchPinTestCase(mode: .sync, expectedSHA: TemplateSyncRunnerTests.branchTipSHA),
            BranchPinTestCase(mode: .update, expectedSHA: TemplateSyncRunnerTests.movedTipSHA),
        ],
    )
    func branchPinAndTip(_ testCase: BranchPinTestCase) async throws {
        let env = try TestEnvironment()
        defer { env.tearDown() }
        try env.seedTemplate(named: "MyTemplate")
        try env.writeManifest("""
        templates:
          - url: \(Self.repoURL)
            branch: main
        """)
        try env.writeLock(branch: "main", revision: Self.branchTipSHA)

        let tagLister = MockGitTagLister(branchRevisions: ["main": Self.movedTipSHA])
        let cloner = MockGitCloner(seedDirectory: env.seedDirectory, fileManager: env.fileManager)

        let result = try await env.runner(mode: testCase.mode, tagLister: tagLister, cloner: cloner).run()

        let entry = try #require(result.scopes.first?.entries.first)
        #expect(entry.resolvedRevision == testCase.expectedSHA)
        #expect(cloner.requestedRefs == [.revision(testCase.expectedSHA)])
    }

    struct BranchPinTestCase: CustomTestStringConvertible {
        let mode: TemplateSyncRunner.SyncMode
        let expectedSHA: String

        var testDescription: String {
            switch mode {
            case .sync: "sync pins the locked SHA"
            case .update: "update follows the branch tip"
            }
        }
    }

    @Test("missing branch surfaces branchNotFound as an entry failure")
    func branchNotFound() async throws {
        let env = try TestEnvironment()
        defer { env.tearDown() }
        try env.writeManifest("""
        templates:
          - url: \(Self.repoURL)
            branch: develop
        """)

        let tagLister = MockGitTagLister(branchRevisions: [:])
        let cloner = MockGitCloner(seedDirectory: env.seedDirectory, fileManager: env.fileManager)

        let result = try await env.runner(mode: .sync, tagLister: tagLister, cloner: cloner).run()

        #expect(result.hasFailures)
        let failure = try #require(result.scopes.first?.entries.first?.failed.first)
        #expect(failure.name == nil)
        #expect(failure.error.localizedDescription.contains("branch 'develop' not found"))
    }

    // MARK: - Local entries

    @Test("local entries install relative to the manifest and are never locked")
    func localEntry() async throws {
        let env = try TestEnvironment()
        defer { env.tearDown() }
        try env.seedTemplate(named: "LocalTemplate", in: env.projectDirectory.appending(path: "local-templates"))
        try env.writeManifest("""
        templates:
          - url: ./local-templates
        """)

        let result = try await env.runner(
            mode: .sync,
            tagLister: MockGitTagLister(failOnListTags: true),
            cloner: MockGitCloner(seedDirectory: env.seedDirectory, fileManager: env.fileManager),
        ).run()

        let entry = try #require(result.scopes.first?.entries.first)
        #expect(entry.installed == ["LocalTemplate"])
        #expect(entry.requirement == nil)
        #expect(env.installedTemplateExists("LocalTemplate"))
        // Nothing to lock: no git entries and no pre-existing lockfile.
        #expect(try LockfileStore(fileManager: env.fileManager).load(lockfilePath: env.lockfileURL) == nil)
    }

    // MARK: - Collisions

    @Test("name collisions: first manifest entry wins, the loser is recorded as failed")
    func nameCollision() async throws {
        let env = try TestEnvironment()
        defer { env.tearDown() }
        let firstDir = env.projectDirectory.appending(path: "first")
        let secondDir = env.projectDirectory.appending(path: "second")
        try env.seedTemplate(named: "Shared", in: firstDir, marker: "first")
        try env.seedTemplate(named: "Shared", in: secondDir, marker: "second")
        try env.writeManifest("""
        templates:
          - url: ./first
          - url: ./second
        """)

        let result = try await env.runner(
            mode: .sync,
            tagLister: MockGitTagLister(failOnListTags: true),
            cloner: MockGitCloner(seedDirectory: env.seedDirectory, fileManager: env.fileManager),
        ).run()

        #expect(result.hasFailures)
        let entries = try #require(result.scopes.first?.entries)
        #expect(entries[0].installed == ["Shared"])
        let failure = try #require(entries[1].failed.first)
        #expect(failure.name == "Shared")
        #expect(failure.error.localizedDescription.contains("first entry in egg.yml wins"))

        let marker = env.projectDirectory
            .appending(path: ".eggs/Shared/marker.txt")
        #expect(try String(decoding: env.fileManager.readFile(at: marker), as: UTF8.self) == "first")
    }

    // MARK: - Failure aggregation

    @Test("a failing entry does not abort the run and its previous pin is preserved")
    func failureAggregationPreservesPin() async throws {
        let env = try TestEnvironment()
        defer { env.tearDown() }
        try env.seedTemplate(named: "MyTemplate")
        let failingURL = "git@github.com:owner/private.git"
        try env.writeManifest("""
        templates:
          - url: \(failingURL)
            from: "1.0.0"
          - url: ./local-templates
        """)
        try env.seedTemplate(named: "LocalTemplate", in: env.projectDirectory.appending(path: "local-templates"))
        try env.writeLock(url: failingURL, version: "1.0.5", tag: "1.0.5", revision: Self.tagSHA)

        let tagLister = MockGitTagLister(error: GitTagLister.Error.lsRemoteFailed(
            url: failingURL,
            exitCode: 128,
            stderr: "Permission denied (publickey).",
        ))
        // The locked 1.0.5 satisfies from: 1.0.0, so sync would reuse the
        // lock; force fresh resolution to exercise the failure path.
        let result = try await env.runner(mode: .update, tagLister: tagLister, cloner: MockGitCloner(
            seedDirectory: env.seedDirectory,
            fileManager: env.fileManager,
        )).run()

        #expect(result.hasFailures)
        let entries = try #require(result.scopes.first?.entries)
        #expect(entries[0].failed.first?.error.localizedDescription.contains("Permission denied") == true)
        #expect(entries[1].installed == ["LocalTemplate"], "the healthy entry still installs")

        let lockfile = try #require(try LockfileStore(fileManager: env.fileManager).load(lockfilePath: env.lockfileURL))
        let preserved = try #require(lockfile.entry(forURL: failingURL))
        #expect(preserved.resolved.version == "1.0.5", "transient failures must not drop the pin")
    }

    // MARK: - Dry run

    @Test("dry-run resolves but installs nothing and writes no lockfile")
    func dryRun() async throws {
        let env = try TestEnvironment()
        defer { env.tearDown() }
        try env.seedTemplate(named: "MyTemplate")
        try env.writeManifest("""
        templates:
          - url: \(Self.repoURL)
            from: "1.0.0"
        """)

        let tagLister = MockGitTagLister(tags: [GitRemoteTag(name: "1.1.0", objectSHA: Self.tagSHA)])
        let cloner = MockGitCloner(seedDirectory: env.seedDirectory, fileManager: env.fileManager)

        let result = try await env.runner(mode: .sync, dryRun: true, tagLister: tagLister, cloner: cloner).run()

        #expect(result.dryRun)
        let entry = try #require(result.scopes.first?.entries.first)
        #expect(entry.resolvedVersion == "1.1.0")
        #expect(entry.installed.isEmpty)
        #expect(cloner.requestedRefs.isEmpty, "dry-run must not clone")
        #expect(!env.installedTemplateExists("MyTemplate"))
        #expect(try LockfileStore(fileManager: env.fileManager).load(lockfilePath: env.lockfileURL) == nil)
    }

    // MARK: - Empty and stale manifests

    @Test("an empty manifest is a warning no-op that still prunes a stale lock")
    func emptyManifestPrunesLock() async throws {
        let env = try TestEnvironment()
        defer { env.tearDown() }
        try env.writeManifest("templates: []")
        try env.writeLock(version: "1.1.0", tag: "v1.1.0", revision: Self.tagSHA)

        let result = try await env.runner(
            mode: .sync,
            tagLister: MockGitTagLister(failOnListTags: true),
            cloner: MockGitCloner(seedDirectory: env.seedDirectory, fileManager: env.fileManager),
        ).run()

        #expect(!result.hasFailures)
        #expect(result.scopes.first?.entries.isEmpty == true)
        let lockfile = try #require(try LockfileStore(fileManager: env.fileManager).load(lockfilePath: env.lockfileURL))
        #expect(lockfile.templates.isEmpty, "entries that left the manifest drop out of the lock")
    }

    @Test("a missing manifest throws rather than aggregating")
    func missingManifestThrows() async throws {
        let env = try TestEnvironment()
        defer { env.tearDown() }

        await #expect(throws: ManifestLoaderError.self) {
            try await env.runner(
                mode: .sync,
                tagLister: MockGitTagLister(failOnListTags: true),
                cloner: MockGitCloner(seedDirectory: env.seedDirectory, fileManager: env.fileManager),
            ).run()
        }
    }
}

// MARK: - Test environment

private struct TestEnvironment {
    let root: URL
    let homeDirectory: URL
    let projectDirectory: URL
    let seedDirectory: URL
    let fileManager: any FileManagerProtocol = FileManager.default

    var manifestURL: URL {
        projectDirectory.appending(path: "egg.yml")
    }

    var lockfileURL: URL {
        projectDirectory.appending(path: "egg-lock.yml")
    }

    init() throws {
        root = try fileManager.makeTemporaryDirectory(prefix: "TemplateSyncRunnerTests")
        homeDirectory = root.appending(path: "home")
        projectDirectory = root.appending(path: "project")
        seedDirectory = root.appending(path: "seed")
        for directory in [homeDirectory, projectDirectory, seedDirectory] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    func tearDown() {
        try? fileManager.removeItem(at: root)
    }

    func runner(
        mode: TemplateSyncRunner.SyncMode,
        dryRun: Bool = false,
        tagLister: MockGitTagLister,
        cloner: MockGitCloner,
    ) -> TemplateSyncRunner {
        TemplateSyncRunner(
            mode: mode,
            dryRun: dryRun,
            scopes: [.init(kind: .project, manifestURL: manifestURL, lockfileURL: lockfileURL)],
            projectDirectory: projectDirectory,
            workingDirectory: projectDirectory,
            homeDirectory: homeDirectory,
            fileManager: fileManager,
            interaction: TestInteraction(),
            gitCloner: cloner,
            tagLister: tagLister,
            directoryCloner: APFSDirectoryCloner(),
            templateDiscoverer: TemplateDiscoverer(fileManager: fileManager),
        )
    }

    func writeManifest(_ yaml: String) throws {
        try fileManager.writeText(yaml, at: manifestURL)
    }

    func seedTemplate(named name: String, in directory: URL? = nil, marker: String = "seed") throws {
        let templateDirectory = (directory ?? seedDirectory).appending(path: name)
        try fileManager.createDirectory(at: templateDirectory, withIntermediateDirectories: true)
        try fileManager.writeText(
            """
            name: "\(name)"
            description: "A test template"
            hatch:
              output: "./output"
            """,
            at: templateDirectory.appending(path: "config.yml"),
        )
        try fileManager.writeText(marker, at: templateDirectory.appending(path: "marker.txt"))
    }

    func installedTemplateExists(_ name: String) -> Bool {
        fileManager.exists(projectDirectory.appending(path: ".eggs").appending(path: name))
    }

    func writeLock(
        url: String = "https://github.com/owner/repo.git",
        version: String? = nil,
        tag: String? = nil,
        branch: String? = nil,
        revision: String,
    ) throws {
        let requirement = if let branch {
            LockedRequirement(.branch(branch))
        } else if let version {
            LockedRequirement(.from(SemanticVersion(version)!))
        } else {
            LockedRequirement(.revision(revision))
        }
        let lockfile = Lockfile(templates: [
            LockedTemplate(
                url: url,
                requirement: requirement,
                resolved: LockedResolution(version: version, tag: tag, branch: branch, revision: revision),
            ),
        ])
        try LockfileStore(fileManager: fileManager).save(lockfile, to: lockfileURL)
    }
}

// MARK: - Mocks

private final class MockGitTagLister: GitTagListing, @unchecked Sendable {
    private let tags: [GitRemoteTag]
    private let branchRevisions: [String: String]
    private let error: (any Error)?
    private let failOnListTags: Bool

    init(
        tags: [GitRemoteTag] = [],
        branchRevisions: [String: String] = [:],
        error: (any Error)? = nil,
        failOnListTags: Bool = false,
    ) {
        self.tags = tags
        self.branchRevisions = branchRevisions
        self.error = error
        self.failOnListTags = failOnListTags
    }

    func listTags(url _: GitURL) async throws -> [GitRemoteTag] {
        if let error {
            throw error
        }
        if failOnListTags {
            Issue.record("listTags must not be called when the lock is reusable")
            return []
        }
        return tags
    }

    func remoteBranchRevision(url _: GitURL, branch: String) async throws -> String? {
        if let error {
            throw error
        }
        return branchRevisions[branch]
    }
}

private final class MockGitCloner: GitCloning, @unchecked Sendable {
    private let seedDirectory: URL
    private let fileManager: any FileManagerProtocol
    private(set) var requestedRefs: [GitRef] = []

    init(seedDirectory: URL, fileManager: any FileManagerProtocol) {
        self.seedDirectory = seedDirectory
        self.fileManager = fileManager
    }

    func clone(url _: GitURL, to destination: URL, ref: GitRef?) async throws {
        if let ref {
            requestedRefs.append(ref)
        }
        let contents = try fileManager.contentsOfDirectory(
            at: seedDirectory,
            includingPropertiesForKeys: nil,
            options: [],
        )
        for item in contents {
            try fileManager.copyItem(at: item, to: destination.appending(path: item.lastPathComponent))
        }
    }
}
