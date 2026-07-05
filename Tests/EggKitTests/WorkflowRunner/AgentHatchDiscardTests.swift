@testable import EggKit
import FileManagerProtocol
import Foundation
import Testing

/// Tests for the unified `discard(token:force:)`: one verb that deletes the
/// transaction directory and its rollback bundle as a pair, from any state,
/// requiring `force` only when an undoable apply is at stake.
@Suite("Discard deletes transaction and rollback bundle as a pair, guarded by force")
struct AgentHatchDiscardTests {
    private let fileManager: some FileManagerProtocol = FileManager.default

    private func makeWorkspace() throws -> URL {
        try fileManager.makeTemporaryDirectory(prefix: "AgentHatchDiscardTests")
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

    private func writeTransaction(token: String, in root: URL, status: HatchTransactionMetadata.Status) throws {
        let store = makeStore(workingDirectory: root)
        _ = try store.createDirectory(for: token)
        try store.save(HatchTransactionMetadata(
            applyToken: token,
            status: status,
            templateName: "t",
            workingDirectory: root.path(percentEncoded: false),
            outputDirectory: root.path(percentEncoded: false),
            workDirectory: store.directory(for: token).appending(path: "work").path(percentEncoded: false),
            referenceDirectory: store.directory(for: token).appending(path: "reference").path(percentEncoded: false),
            changes: [StoredChangeEntry(path: "hello.txt", kind: "add")],
            warnings: [],
            rollbackId: status == .preview ? nil : token,
        ))
    }

    private func writeBundle(id: String, in root: URL, status: String?) throws {
        let bundleRoot = root.appending(path: ".egg/rollback/\(id)")
        try fileManager.createDirectory(at: bundleRoot.appending(path: "before"), withIntermediateDirectories: true)
        let statusLine = status.map { "\"status\": \"\($0)\"," } ?? ""
        let manifest = """
        {
          "id": "\(id)",
          "applyToken": "\(id)",
          "templateName": "t",
          "workingDirectory": "\(root.path(percentEncoded: false))",
          \(statusLine)
          "changes": [{"path": "hello.txt", "kind": "add", "afterHash": null}]
        }
        """
        try fileManager.writeText(manifest, at: bundleRoot.appending(path: "manifest.json"))
    }

    private func transactionDir(_ root: URL, _ token: String) -> URL {
        root.appending(path: ".egg/transactions/\(token)")
    }

    private func bundleDir(_ root: URL, _ token: String) -> URL {
        root.appending(path: ".egg/rollback/\(token)")
    }

    @Test("Discarding a preview deletes the transaction and tolerates the absent bundle")
    func discardingAPreviewDeletesTheTransaction() async throws {
        let root = try makeWorkspace()
        defer { try? fileManager.removeItem(at: root) }
        try writeTransaction(token: "tx", in: root, status: .preview)

        let result = try await makeRunner(workingDirectory: root).discard(token: "tx")

        #expect(result.status == "discarded")
        #expect(result.rollbackId == nil)
        #expect(!fileManager.exists(transactionDir(root, "tx")))
    }

    @Test("Discarding an applied transaction refuses without force and deletes nothing")
    func discardingAnAppliedTransactionRefusesWithoutForce() async throws {
        let root = try makeWorkspace()
        defer { try? fileManager.removeItem(at: root) }
        try writeTransaction(token: "tx", in: root, status: .applied)
        try writeBundle(id: "tx", in: root, status: "applied")
        let runner = makeRunner(workingDirectory: root)

        await #expect(throws: AgentHatchTransactionRunner.Error.discardRequiresForce(token: "tx", status: "applied")) {
            try await runner.discard(token: "tx")
        }
        #expect(fileManager.exists(transactionDir(root, "tx")))
        #expect(fileManager.exists(bundleDir(root, "tx")))
    }

    @Test("Discarding an applied transaction with force deletes both directories")
    func discardingAnAppliedTransactionWithForceDeletesBoth() async throws {
        let root = try makeWorkspace()
        defer { try? fileManager.removeItem(at: root) }
        try writeTransaction(token: "tx", in: root, status: .applied)
        try writeBundle(id: "tx", in: root, status: "applied")

        let result = try await makeRunner(workingDirectory: root).discard(token: "tx", force: true)

        #expect(result.status == "discarded")
        #expect(result.rollbackId == "tx")
        #expect(!fileManager.exists(transactionDir(root, "tx")))
        #expect(!fileManager.exists(bundleDir(root, "tx")))
    }

    @Test("Discarding a rolledBack transaction deletes both directories without force")
    func discardingARolledBackTransactionDeletesBothWithoutForce() async throws {
        let root = try makeWorkspace()
        defer { try? fileManager.removeItem(at: root) }
        try writeTransaction(token: "tx", in: root, status: .rolledBack)
        try writeBundle(id: "tx", in: root, status: "rolledBack")

        let result = try await makeRunner(workingDirectory: root).discard(token: "tx")

        #expect(result.status == "discarded")
        #expect(!fileManager.exists(transactionDir(root, "tx")))
        #expect(!fileManager.exists(bundleDir(root, "tx")))
    }

    @Test("An orphaned applied bundle requires force; a rolledBack one does not")
    func anOrphanedBundleFollowsItsManifestStatus() async throws {
        let root = try makeWorkspace()
        defer { try? fileManager.removeItem(at: root) }
        let runner = makeRunner(workingDirectory: root)

        // Legacy bundle without a status field counts as applied.
        try writeBundle(id: "legacy", in: root, status: nil)
        await #expect(throws: AgentHatchTransactionRunner.Error.discardRequiresForce(token: "legacy", status: "applied")) {
            try await runner.discard(token: "legacy")
        }
        let forced = try await runner.discard(token: "legacy", force: true)
        #expect(forced.status == "discarded")
        #expect(!fileManager.exists(bundleDir(root, "legacy")))
        #expect(!fileManager.exists(transactionDir(root, "legacy")))

        try writeBundle(id: "done", in: root, status: "rolledBack")
        let result = try await runner.discard(token: "done")
        #expect(result.status == "discarded")
        #expect(!fileManager.exists(bundleDir(root, "done")))
        #expect(!fileManager.exists(transactionDir(root, "done")))
    }

    @Test("Discarding an unknown token throws transactionNotFound")
    func discardingAnUnknownTokenThrowsTransactionNotFound() async throws {
        let root = try makeWorkspace()
        defer { try? fileManager.removeItem(at: root) }
        let runner = makeRunner(workingDirectory: root)

        await #expect(throws: AgentHatchTransactionRunner.Error.transactionNotFound(token: "ghost")) {
            try await runner.discard(token: "ghost")
        }
        // Neither lock's directory creation may leave a shell behind — a
        // rollback-side ghost would list as orphanedRollback forever.
        #expect(!fileManager.exists(transactionDir(root, "ghost")))
        #expect(!fileManager.exists(bundleDir(root, "ghost")))
        #expect(makeRunner(workingDirectory: root).transactions().transactions.isEmpty)
    }

    @Test("Corrupt metadata requires force, then deletes the pair")
    func corruptMetadataRequiresForce() async throws {
        let root = try makeWorkspace()
        defer { try? fileManager.removeItem(at: root) }
        let store = makeStore(workingDirectory: root)
        _ = try store.createDirectory(for: "bad")
        try fileManager.writeText("not json", at: store.metadataURL(for: "bad"))
        let runner = makeRunner(workingDirectory: root)

        await #expect(throws: AgentHatchTransactionRunner.Error.discardRequiresForce(token: "bad", status: "corrupt")) {
            try await runner.discard(token: "bad")
        }
        let result = try await runner.discard(token: "bad", force: true)
        #expect(result.status == "discarded")
        #expect(!fileManager.exists(transactionDir(root, "bad")))
    }
}
