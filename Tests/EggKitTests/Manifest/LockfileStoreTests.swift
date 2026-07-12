@testable import EggKit
import FileManagerProtocol
import Foundation
import Testing

struct LockfileStoreTests {
    private let fileManager: some FileManagerProtocol = FileManager.default

    @Test("round-trips every requirement kind")
    func roundTrip() throws {
        let lockfile = Lockfile(templates: [
            LockedTemplate(
                url: "https://github.com/a/from-repo.git",
                requirement: LockedRequirement(.from(SemanticVersion(major: 1, minor: 0, patch: 0))),
                resolved: LockedResolution(
                    version: "1.1.0",
                    tag: "v1.1.0",
                    revision: "97117bc42b44f33e0d04b543b815ad9f3079f25e",
                ),
            ),
            LockedTemplate(
                url: "https://github.com/b/exact-repo.git",
                requirement: LockedRequirement(.exact(SemanticVersion(major: 1, minor: 2, patch: 0))),
                resolved: LockedResolution(
                    version: "1.2.0",
                    tag: "1.2.0",
                    revision: "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2",
                ),
            ),
            LockedTemplate(
                url: "git@github.com:c/branch-repo.git",
                requirement: LockedRequirement(.branch("main")),
                resolved: LockedResolution(
                    branch: "main",
                    revision: "d4e5f6a7b8c9d4e5f6a7b8c9d4e5f6a7b8c9d4e5",
                ),
            ),
            LockedTemplate(
                url: "https://github.com/d/revision-repo.git",
                requirement: LockedRequirement(.revision("6c0f1a2b9d8e7f6a5b4c3d2e1f0a9b8c7d6e5f4a")),
                resolved: LockedResolution(revision: "6c0f1a2b9d8e7f6a5b4c3d2e1f0a9b8c7d6e5f4a"),
            ),
        ])

        let root = try fileManager.makeTemporaryDirectory(prefix: "LockfileStoreTests")
        defer { try? fileManager.removeItem(at: root) }
        let lockPath = root.appending(path: "egg-lock.yml")

        let store = LockfileStore(fileManager: fileManager)
        try store.save(lockfile, to: lockPath)
        let loaded = try #require(try store.load(lockfilePath: lockPath))

        #expect(loaded.version == Lockfile.currentVersion)
        #expect(loaded.templates == lockfile.templates.sorted { $0.url < $1.url })
        #expect(loaded.entry(forURL: "git@github.com:c/branch-repo.git")?.resolved.branch == "main")
        #expect(
            loaded.entry(forURL: "https://github.com/a/from-repo.git")?.resolved.semanticVersion
                == SemanticVersion(major: 1, minor: 1, patch: 0),
        )
    }

    @Test("writes are stable: entries sorted by url regardless of input order")
    func stableOutput() throws {
        let first = LockedTemplate(
            url: "https://github.com/a/repo.git",
            requirement: LockedRequirement(.branch("main")),
            resolved: LockedResolution(branch: "main", revision: String(repeating: "a", count: 40)),
        )
        let second = LockedTemplate(
            url: "https://github.com/b/repo.git",
            requirement: LockedRequirement(.branch("main")),
            resolved: LockedResolution(branch: "main", revision: String(repeating: "b", count: 40)),
        )

        let root = try fileManager.makeTemporaryDirectory(prefix: "LockfileStoreTests")
        defer { try? fileManager.removeItem(at: root) }
        let store = LockfileStore(fileManager: fileManager)

        let forwardPath = root.appending(path: "forward.yml")
        let reversedPath = root.appending(path: "reversed.yml")
        try store.save(Lockfile(templates: [first, second]), to: forwardPath)
        try store.save(Lockfile(templates: [second, first]), to: reversedPath)

        let forward = try fileManager.readFile(at: forwardPath)
        let reversed = try fileManager.readFile(at: reversedPath)
        #expect(forward == reversed)
    }

    @Test("nil resolution fields are omitted from the YAML")
    func nilFieldsOmitted() throws {
        let lockfile = Lockfile(templates: [
            LockedTemplate(
                url: "https://github.com/d/revision-repo.git",
                requirement: LockedRequirement(.revision(String(repeating: "c", count: 40))),
                resolved: LockedResolution(revision: String(repeating: "c", count: 40)),
            ),
        ])

        let root = try fileManager.makeTemporaryDirectory(prefix: "LockfileStoreTests")
        defer { try? fileManager.removeItem(at: root) }
        let lockPath = root.appending(path: "egg-lock.yml")
        try LockfileStore(fileManager: fileManager).save(lockfile, to: lockPath)

        let yaml = try String(decoding: fileManager.readFile(at: lockPath), as: UTF8.self)
        #expect(yaml.contains("version: 1"))
        #expect(yaml.contains("revision:"))
        #expect(!yaml.contains("tag:"))
        #expect(!yaml.contains("branch:"))
        #expect(!yaml.contains("from:"))
    }

    @Test("missing lockfile loads as nil, not an error")
    func missingLockfile() throws {
        let root = try fileManager.makeTemporaryDirectory(prefix: "LockfileStoreTests")
        defer { try? fileManager.removeItem(at: root) }

        let loaded = try LockfileStore(fileManager: fileManager)
            .load(lockfilePath: root.appending(path: "egg-lock.yml"))
        #expect(loaded == nil)
    }

    @Test("malformed lockfile throws decodingFailed")
    func malformedLockfile() throws {
        let root = try fileManager.makeTemporaryDirectory(prefix: "LockfileStoreTests")
        defer { try? fileManager.removeItem(at: root) }
        let lockPath = root.appending(path: "egg-lock.yml")
        try fileManager.writeText("version: [broken", at: lockPath)

        #expect {
            try LockfileStore(fileManager: fileManager).load(lockfilePath: lockPath)
        } throws: { error in
            guard case LockfileError.decodingFailed = error else {
                return false
            }
            return true
        }
    }
}
