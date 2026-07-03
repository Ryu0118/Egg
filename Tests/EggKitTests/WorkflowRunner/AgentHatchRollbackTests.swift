@testable import EggKit
import FileManagerProtocol
import Foundation
import Testing

/// Edge-case tests for `AgentHatchTransactionRunner.rollback(id:force:)`.
///
/// Rollback only reads `.egg/rollback/<id>/{manifest.json,before/}` and the
/// working directory, so each test synthesizes a bundle directly — no git,
/// no staging, no template expansion.
@Suite("AgentHatchRollback")
struct AgentHatchRollbackTests {
    private let fileManager: some FileManagerProtocol = FileManager.default

    private func makeWorkspace() throws -> URL {
        try fileManager.makeTemporaryDirectory(prefix: "AgentHatchRollbackTests")
    }

    private func makeRunner(workingDirectory: URL) -> AgentHatchTransactionRunner {
        AgentHatchTransactionRunner(
            fileManager: fileManager,
            workingDirectory: workingDirectory,
            homeDirectory: workingDirectory,
            templateDirectory: workingDirectory,
            config: Config(name: "t", description: "t", hatch: .init(output: ".")),
            parsedMacros: [],
        )
    }

    private func hash(_ text: String) -> String {
        AgentHatchTransactionRunner.sha256(of: Data(text.utf8))
    }

    /// Writes a rollback bundle to `.egg/rollback/<id>/`.
    private func writeBundle(
        id: String,
        in root: URL,
        changes: [(path: String, kind: String, afterHash: String?)],
        beforeFiles: [String: String] = [:],
    ) throws {
        let bundleRoot = root.appending(path: ".egg/rollback/\(id)")
        try fileManager.createDirectory(at: bundleRoot.appending(path: "before"), withIntermediateDirectories: true)
        for (path, contents) in beforeFiles {
            try fileManager.writeText(contents, at: bundleRoot.appending(path: "before/\(path)"))
        }
        let changesJSON = changes.map { change in
            let afterHash = change.afterHash.map { "\"\($0)\"" } ?? "null"
            return "{\"path\": \"\(change.path)\", \"kind\": \"\(change.kind)\", \"afterHash\": \(afterHash)}"
        }
        .joined(separator: ",")
        let manifest = """
        {
          "id": "\(id)",
          "applyToken": "\(id)",
          "templateName": "t",
          "workingDirectory": "\(root.path(percentEncoded: false))",
          "status": "applied",
          "changes": [\(changesJSON)]
        }
        """
        try fileManager.writeText(manifest, at: bundleRoot.appending(path: "manifest.json"))
    }

    @Test
    func `Restores modify and delete, removes add, leaves unrelated files intact`() async throws {
        let root = try makeWorkspace()
        defer { try? fileManager.removeItem(at: root) }

        // Post-apply state: added.txt exists, modified.txt has new content,
        // deleted.txt is gone, unrelated.txt untouched.
        try fileManager.writeText("added\n", at: root.appending(path: "added.txt"))
        try fileManager.writeText("new\n", at: root.appending(path: "modified.txt"))
        try fileManager.writeText("unrelated\n", at: root.appending(path: "unrelated.txt"))

        try writeBundle(
            id: "rb",
            in: root,
            changes: [
                ("added.txt", "add", hash("added\n")),
                ("modified.txt", "modify", hash("new\n")),
                ("deleted.txt", "delete", nil),
            ],
            beforeFiles: [
                "modified.txt": "old\n",
                "deleted.txt": "bring me back\n",
            ],
        )

        let result = try await makeRunner(workingDirectory: root).rollback(id: "rb")
        #expect(result.status == "rolledBack")
        #expect(!fileManager.exists(root.appending(path: "added.txt")))
        #expect(try String(decoding: fileManager.readFile(at: root.appending(path: "modified.txt")), as: UTF8.self) == "old\n")
        #expect(try String(decoding: fileManager.readFile(at: root.appending(path: "deleted.txt")), as: UTF8.self) == "bring me back\n")
        #expect(try String(decoding: fileManager.readFile(at: root.appending(path: "unrelated.txt")), as: UTF8.self) == "unrelated\n")
    }

    @Test
    func `Refuses when the user edited an applied file, unless forced`() async throws {
        let root = try makeWorkspace()
        defer { try? fileManager.removeItem(at: root) }

        // Apply left "new"; the user then edited it to "user edit".
        try fileManager.writeText("user edit\n", at: root.appending(path: "modified.txt"))
        try writeBundle(
            id: "rb",
            in: root,
            changes: [("modified.txt", "modify", hash("new\n"))],
            beforeFiles: ["modified.txt": "old\n"],
        )
        let runner = makeRunner(workingDirectory: root)

        await #expect(throws: AgentHatchTransactionRunner.Error.conflictingRollbackChanges(["modified.txt"])) {
            try await runner.rollback(id: "rb")
        }
        // The user's edit must survive a refused rollback.
        #expect(try String(decoding: fileManager.readFile(at: root.appending(path: "modified.txt")), as: UTF8.self) == "user edit\n")

        // force overrides and restores the before content.
        let result = try await runner.rollback(id: "rb", force: true)
        #expect(result.status == "rolledBack")
        #expect(try String(decoding: fileManager.readFile(at: root.appending(path: "modified.txt")), as: UTF8.self) == "old\n")
    }

    @Test
    func `Refuses a second rollback of the same bundle`() async throws {
        let root = try makeWorkspace()
        defer { try? fileManager.removeItem(at: root) }

        try fileManager.writeText("added\n", at: root.appending(path: "added.txt"))
        try writeBundle(id: "rb", in: root, changes: [("added.txt", "add", hash("added\n"))])
        let runner = makeRunner(workingDirectory: root)

        _ = try await runner.rollback(id: "rb")
        await #expect(throws: AgentHatchTransactionRunner.Error.alreadyRolledBack(id: "rb")) {
            try await runner.rollback(id: "rb")
        }
    }

    @Test
    func `A user-recreated file at a delete path is a conflict`() async throws {
        let root = try makeWorkspace()
        defer { try? fileManager.removeItem(at: root) }

        // Apply deleted the file; the user recreated it afterwards.
        try fileManager.writeText("recreated\n", at: root.appending(path: "deleted.txt"))
        try writeBundle(
            id: "rb",
            in: root,
            changes: [("deleted.txt", "delete", nil)],
            beforeFiles: ["deleted.txt": "original\n"],
        )
        let runner = makeRunner(workingDirectory: root)

        await #expect(throws: AgentHatchTransactionRunner.Error.conflictingRollbackChanges(["deleted.txt"])) {
            try await runner.rollback(id: "rb")
        }
        let forced = try await runner.rollback(id: "rb", force: true)
        #expect(forced.status == "rolledBack")
        #expect(try String(decoding: fileManager.readFile(at: root.appending(path: "deleted.txt")), as: UTF8.self) == "original\n")
    }

    @Test
    func `An add path whose pre-apply file was backed up is restored, not deleted`() async throws {
        let root = try makeWorkspace()
        defer { try? fileManager.removeItem(at: root) }

        // A forced apply overwrote the user's file at an "add" path; the bundle
        // backed the original up. Rollback must bring it back.
        try fileManager.writeText("template content\n", at: root.appending(path: "added.txt"))
        try writeBundle(
            id: "rb",
            in: root,
            changes: [("added.txt", "add", hash("template content\n"))],
            beforeFiles: ["added.txt": "the user's file\n"],
        )

        _ = try await makeRunner(workingDirectory: root).rollback(id: "rb")
        #expect(try String(decoding: fileManager.readFile(at: root.appending(path: "added.txt")), as: UTF8.self) == "the user's file\n")
    }

    @Test
    func `A missing add target is not a conflict; rollback is a no-op for it`() async throws {
        let root = try makeWorkspace()
        defer { try? fileManager.removeItem(at: root) }

        // The user already deleted the added file before rolling back.
        try writeBundle(id: "rb", in: root, changes: [("added.txt", "add", hash("added\n"))])

        let result = try await makeRunner(workingDirectory: root).rollback(id: "rb")
        #expect(result.status == "rolledBack")
        #expect(!fileManager.exists(root.appending(path: "added.txt")))
    }

    @Test
    func `Removing a nested added file prunes now-empty parent directories`() async throws {
        let root = try makeWorkspace()
        defer { try? fileManager.removeItem(at: root) }

        let nested = root.appending(path: "deep/nested")
        try fileManager.createDirectory(at: nested, withIntermediateDirectories: true)
        try fileManager.writeText("x\n", at: nested.appending(path: "new.txt"))
        try writeBundle(id: "rb", in: root, changes: [("deep/nested/new.txt", "add", hash("x\n"))])

        _ = try await makeRunner(workingDirectory: root).rollback(id: "rb")
        #expect(!fileManager.exists(root.appending(path: "deep")))
        #expect(fileManager.exists(root))
    }

    @Test
    func `A non-empty parent directory survives pruning`() async throws {
        let root = try makeWorkspace()
        defer { try? fileManager.removeItem(at: root) }

        let nested = root.appending(path: "deep/nested")
        try fileManager.createDirectory(at: nested, withIntermediateDirectories: true)
        try fileManager.writeText("x\n", at: nested.appending(path: "new.txt"))
        try fileManager.writeText("keep\n", at: root.appending(path: "deep/keep.txt"))
        try writeBundle(id: "rb", in: root, changes: [("deep/nested/new.txt", "add", hash("x\n"))])

        _ = try await makeRunner(workingDirectory: root).rollback(id: "rb")
        #expect(!fileManager.exists(root.appending(path: "deep/nested")))
        #expect(fileManager.exists(root.appending(path: "deep/keep.txt")))
    }

    @Test
    func `Missing bundle id fails with a read error`() async throws {
        let root = try makeWorkspace()
        defer { try? fileManager.removeItem(at: root) }

        await #expect(throws: (any Error).self) {
            try await makeRunner(workingDirectory: root).rollback(id: "nope")
        }
    }

    @Test
    func `Legacy bundle without afterHash skips conflict detection but still restores`() async throws {
        let root = try makeWorkspace()
        defer { try? fileManager.removeItem(at: root) }

        try fileManager.writeText("whatever the user did\n", at: root.appending(path: "modified.txt"))
        try writeBundle(
            id: "rb",
            in: root,
            changes: [("modified.txt", "modify", nil)],
            beforeFiles: ["modified.txt": "old\n"],
        )

        let result = try await makeRunner(workingDirectory: root).rollback(id: "rb")
        #expect(result.status == "rolledBack")
        #expect(try String(decoding: fileManager.readFile(at: root.appending(path: "modified.txt")), as: UTF8.self) == "old\n")
    }

    @Test
    func `A missing modify backup refuses up front instead of a partial silent restore`() async throws {
        let root = try makeWorkspace()
        defer { try? fileManager.removeItem(at: root) }

        // Two changes, but only one has a "before" backup on disk — simulating
        // a corrupted/incomplete bundle.
        try fileManager.writeText("current a\n", at: root.appending(path: "a.txt"))
        try fileManager.writeText("current b\n", at: root.appending(path: "b.txt"))
        try writeBundle(
            id: "rb",
            in: root,
            changes: [
                ("a.txt", "modify", hash("current a\n")),
                ("b.txt", "modify", hash("current b\n")),
            ],
            beforeFiles: ["a.txt": "old a\n"], // b.txt's backup is missing
        )

        await #expect(throws: AgentHatchTransactionRunner.Error.missingRollbackBackup(id: "rb", paths: ["b.txt"])) {
            try await makeRunner(workingDirectory: root).rollback(id: "rb")
        }
        // Nothing must have been touched — not even a.txt, whose backup DID exist.
        #expect(try String(decoding: fileManager.readFile(at: root.appending(path: "a.txt")), as: UTF8.self) == "current a\n")
        #expect(try String(decoding: fileManager.readFile(at: root.appending(path: "b.txt")), as: UTF8.self) == "current b\n")
    }

    @Test
    func `A missing delete backup also refuses up front`() async throws {
        let root = try makeWorkspace()
        defer { try? fileManager.removeItem(at: root) }

        try writeBundle(id: "rb", in: root, changes: [("deleted.txt", "delete", nil)])
        // No beforeFiles at all — the backup is missing.

        await #expect(throws: AgentHatchTransactionRunner.Error.missingRollbackBackup(id: "rb", paths: ["deleted.txt"])) {
            try await makeRunner(workingDirectory: root).rollback(id: "rb")
        }
    }

    @Test(arguments: ["../escape", "a/b", "..", "", "a\\b"])
    func `Rejects a rollback id that is not a single safe path segment`(badId: String) async throws {
        let root = try makeWorkspace()
        defer { try? fileManager.removeItem(at: root) }

        await #expect(throws: AgentHatchTransactionRunner.Error.self) {
            try await makeRunner(workingDirectory: root).rollback(id: badId)
        }
    }

    @Test(arguments: ["../escape", "a/b", "..", ""])
    func `Rejects an apply token that is not a single safe path segment`(badToken: String) async throws {
        let root = try makeWorkspace()
        defer { try? fileManager.removeItem(at: root) }

        await #expect(throws: AgentHatchTransactionRunner.Error.self) {
            try await makeRunner(workingDirectory: root).apply(token: badToken)
        }
        await #expect(throws: AgentHatchTransactionRunner.Error.self) {
            try await makeRunner(workingDirectory: root).discard(token: badToken)
        }
    }

    @Test
    func `A rollback id that would escape via path traversal cannot read outside .egg-rollback`() async throws {
        let root = try makeWorkspace()
        defer { try? fileManager.removeItem(at: root) }

        // Plant a real manifest OUTSIDE .egg/rollback to prove traversal would
        // have worked if the identifier were not validated.
        let secretRoot = root.appending(path: "secret/before")
        try fileManager.createDirectory(at: secretRoot, withIntermediateDirectories: true)
        try fileManager.writeText(
            """
            {"id": "x", "applyToken": "x", "templateName": "t", "workingDirectory": "\(root.path(percentEncoded: false))", "status": "applied", "changes": []}
            """,
            at: root.appending(path: "secret/manifest.json"),
        )

        await #expect(throws: AgentHatchTransactionRunner.Error.self) {
            try await makeRunner(workingDirectory: root).rollback(id: "../secret")
        }
    }
}
