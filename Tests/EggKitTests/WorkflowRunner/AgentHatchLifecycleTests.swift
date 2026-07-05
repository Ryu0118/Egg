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
