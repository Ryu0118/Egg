@testable import EggKit
import FileManagerProtocol
import Foundation
import Testing

/// Tests for the unified transaction state machine:
/// preview → applied ⇄ rolledBack, with metadata.json as the single source
/// of truth for status.
@Suite("Transaction status transitions stay in sync across metadata and rollback manifest")
struct AgentHatchLifecycleTests {
    private let fileManager: some FileManagerProtocol = FileManager.default

    private func makeWorkspace() throws -> URL {
        try fileManager.makeTemporaryDirectory(prefix: "AgentHatchLifecycleTests")
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

    private func makeStore(workingDirectory: URL) -> HatchTransactionStore {
        HatchTransactionStore(fileManager: fileManager, workingDirectory: workingDirectory)
    }

    private func hash(_ text: String) -> String {
        AgentHatchTransactionRunner.sha256(of: Data(text.utf8))
    }

    /// Writes `.egg/transactions/<token>/metadata.json` plus `work/` and
    /// `reference/` trees, as a completed preview (or apply) would have.
    private func writeTransaction(
        token: String,
        in root: URL,
        status: HatchTransactionMetadata.Status,
        changes: [(path: String, kind: String)],
        workFiles: [String: String] = [:],
        rollbackId: String? = nil,
    ) throws {
        let store = makeStore(workingDirectory: root)
        let directory = try store.createDirectory(for: token)
        let work = directory.appending(path: "work")
        let reference = directory.appending(path: "reference")
        try fileManager.createDirectory(at: work, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: reference, withIntermediateDirectories: true)
        for (path, contents) in workFiles {
            try fileManager.writeText(contents, at: work.appending(path: path))
        }
        try store.save(HatchTransactionMetadata(
            applyToken: token,
            status: status,
            templateName: "t",
            workingDirectory: root.path(percentEncoded: false),
            outputDirectory: root.path(percentEncoded: false),
            workDirectory: work.path(percentEncoded: false),
            referenceDirectory: reference.path(percentEncoded: false),
            changes: changes.map { StoredChangeEntry(path: $0.path, kind: $0.kind) },
            warnings: [],
            rollbackId: rollbackId,
        ))
    }

    /// Writes `.egg/rollback/<id>/` with a manifest and before-backups.
    private func writeBundle(
        id: String,
        in root: URL,
        status: String = "applied",
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
          "status": "\(status)",
          "changes": [\(changesJSON)]
        }
        """
        try fileManager.writeText(manifest, at: bundleRoot.appending(path: "manifest.json"))
    }

    @Test("Rollback marks the transaction rolledBack in metadata.json, not just the manifest")
    func rollbackMarksTheTransactionRolledBackInMetadata() async throws {
        let root = try makeWorkspace()
        defer { try? fileManager.removeItem(at: root) }

        try fileManager.writeText("added\n", at: root.appending(path: "added.txt"))
        try writeTransaction(
            token: "tx",
            in: root,
            status: .applied,
            changes: [("added.txt", "add")],
            rollbackId: "tx",
        )
        try writeBundle(id: "tx", in: root, changes: [("added.txt", "add", hash("added\n"))])

        let result = try await makeRunner(workingDirectory: root).rollback(id: "tx")

        #expect(result.status == "rolledBack")
        let metadata = try makeStore(workingDirectory: root).load(token: "tx")
        #expect(metadata.status == .rolledBack)
        #expect(metadata.rollbackId == "tx")
    }

    @Test("Re-apply after rollback restores files, replaces the bundle, and warns")
    func reapplyAfterRollbackRestoresFilesReplacesTheBundleAndWarns() async throws {
        let root = try makeWorkspace()
        defer { try? fileManager.removeItem(at: root) }
        let runner = makeRunner(workingDirectory: root)

        try writeTransaction(
            token: "tx",
            in: root,
            status: .preview,
            changes: [("hello.txt", "add")],
            workFiles: ["hello.txt": "hello\n"],
        )

        let first = try await runner.apply(token: "tx")
        #expect(first.status == "applied")
        #expect(first.warnings.isEmpty)

        _ = try await runner.rollback(id: "tx")
        #expect(!fileManager.exists(root.appending(path: "hello.txt")))

        // Plant a stale leftover in the consumed bundle: re-apply must replace
        // the bundle wholesale, not merge fresh backups into it.
        let staleBackup = root.appending(path: ".egg/rollback/tx/before/stale.txt")
        try fileManager.writeText("stale\n", at: staleBackup)

        let second = try await runner.apply(token: "tx")

        #expect(second.status == "applied")
        #expect(second.rollbackId == "tx")
        #expect(second.warnings.contains { $0.code == "reapplied_after_rollback" })
        #expect(try String(decoding: fileManager.readFile(at: root.appending(path: "hello.txt")), as: UTF8.self) == "hello\n")
        #expect(!fileManager.exists(staleBackup))
        #expect(try makeStore(workingDirectory: root).load(token: "tx").status == .applied)
    }

    @Test("A re-applied transaction can be rolled back again")
    func aReappliedTransactionCanBeRolledBackAgain() async throws {
        let root = try makeWorkspace()
        defer { try? fileManager.removeItem(at: root) }
        let runner = makeRunner(workingDirectory: root)

        try writeTransaction(
            token: "tx",
            in: root,
            status: .preview,
            changes: [("hello.txt", "add")],
            workFiles: ["hello.txt": "hello\n"],
        )
        _ = try await runner.apply(token: "tx")
        _ = try await runner.rollback(id: "tx")
        _ = try await runner.apply(token: "tx")

        let result = try await runner.rollback(id: "tx")

        #expect(result.status == "rolledBack")
        #expect(!fileManager.exists(root.appending(path: "hello.txt")))
        #expect(try makeStore(workingDirectory: root).load(token: "tx").status == .rolledBack)
    }

    @Test("Apply refuses an applied transaction and points at rollback")
    func applyRefusesAnAppliedTransaction() async throws {
        let root = try makeWorkspace()
        defer { try? fileManager.removeItem(at: root) }
        let runner = makeRunner(workingDirectory: root)

        try writeTransaction(
            token: "tx",
            in: root,
            status: .preview,
            changes: [("hello.txt", "add")],
            workFiles: ["hello.txt": "hello\n"],
        )
        _ = try await runner.apply(token: "tx")

        await #expect(throws: AgentHatchTransactionRunner.Error.transactionNotApplicable(token: "tx", status: "applied")) {
            try await runner.apply(token: "tx")
        }
    }

    @Test("A forced apply overwrites a user file at an add path, and rollback restores it")
    func aForcedApplyOverwritesAUserFileAndRollbackRestoresIt() async throws {
        let root = try makeWorkspace()
        defer { try? fileManager.removeItem(at: root) }
        let runner = makeRunner(workingDirectory: root)

        try writeTransaction(
            token: "tx",
            in: root,
            status: .preview,
            changes: [("hello.txt", "add")],
            workFiles: ["hello.txt": "template\n"],
        )
        // The user creates a file at the add path after the preview.
        try fileManager.writeText("user content\n", at: root.appending(path: "hello.txt"))

        // Unforced apply must refuse the conflict.
        await #expect(throws: AgentHatchTransactionRunner.Error.conflictingWorkingDirectoryChanges(["hello.txt"])) {
            try await runner.apply(token: "tx")
        }

        // Forced apply overwrites.
        let applied = try await runner.apply(token: "tx", force: true)
        #expect(applied.status == "applied")
        #expect(try String(decoding: fileManager.readFile(at: root.appending(path: "hello.txt")), as: UTF8.self) == "template\n")

        // Rollback brings the user's file back instead of just deleting.
        _ = try await runner.rollback(id: "tx")
        #expect(try String(decoding: fileManager.readFile(at: root.appending(path: "hello.txt")), as: UTF8.self) == "user content\n")
    }

    @Test("Applying an unknown token fails with transactionNotFound and leaves no shell")
    func applyingAnUnknownTokenFailsWithTransactionNotFound() async throws {
        let root = try makeWorkspace()
        defer { try? fileManager.removeItem(at: root) }
        let runner = makeRunner(workingDirectory: root)

        await #expect(throws: AgentHatchTransactionRunner.Error.transactionNotFound(token: "ghost")) {
            try await runner.apply(token: "ghost")
        }
        #expect(!fileManager.exists(root.appending(path: ".egg/transactions/ghost")))
    }

    @Test("Applying a transaction with corrupt metadata fails with a guided error")
    func applyingATransactionWithCorruptMetadataFailsWithAGuidedError() async throws {
        let root = try makeWorkspace()
        defer { try? fileManager.removeItem(at: root) }
        let store = makeStore(workingDirectory: root)
        _ = try store.createDirectory(for: "bad")
        try fileManager.writeText("not json", at: store.metadataURL(for: "bad"))

        await #expect(throws: AgentHatchTransactionRunner.Error.corruptTransactionRecord(token: "bad")) {
            try await makeRunner(workingDirectory: root).apply(token: "bad")
        }
    }

    @Test("Rollback of an orphaned bundle succeeds and leaves no transaction shell behind")
    func rollbackOfAnOrphanedBundleLeavesNoTransactionShell() async throws {
        let root = try makeWorkspace()
        defer { try? fileManager.removeItem(at: root) }

        try fileManager.writeText("added\n", at: root.appending(path: "added.txt"))
        // Pre-unification discard removed .egg/transactions/<id> but left the bundle.
        try writeBundle(id: "orphan", in: root, changes: [("added.txt", "add", hash("added\n"))])

        let result = try await makeRunner(workingDirectory: root).rollback(id: "orphan")

        #expect(result.status == "rolledBack")
        #expect(!fileManager.exists(root.appending(path: "added.txt")))
        // The transactions lock creates the directory it locks; rollback must
        // clean up that shell when no metadata exists.
        #expect(!fileManager.exists(root.appending(path: ".egg/transactions/orphan")))
    }
}
