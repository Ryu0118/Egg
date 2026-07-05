@testable import EggKit
import FileManagerProtocol
import Foundation
import Testing

@Suite("HatchTransactionStore persists and transitions transaction status")
struct HatchTransactionStoreTests {
    private let fileManager: some FileManagerProtocol = FileManager.default

    private func makeWorkspace() throws -> URL {
        try fileManager.makeTemporaryDirectory(prefix: "HatchTransactionStoreTests")
    }

    private func makeStore(workingDirectory: URL) -> HatchTransactionStore {
        HatchTransactionStore(fileManager: fileManager, workingDirectory: workingDirectory)
    }

    private func makeMetadata(token: String, root: URL, status: HatchTransactionMetadata.Status = .preview) -> HatchTransactionMetadata {
        HatchTransactionMetadata(
            applyToken: token,
            status: status,
            templateName: "t",
            workingDirectory: root.path(percentEncoded: false),
            outputDirectory: root.path(percentEncoded: false),
            workDirectory: root.appending(path: ".egg/transactions/\(token)/work").path(percentEncoded: false),
            referenceDirectory: root.appending(path: ".egg/transactions/\(token)/reference").path(percentEncoded: false),
            changes: [],
            warnings: [],
            rollbackId: nil,
        )
    }

    @Test("markRolledBackIfPresent flips status and keeps rollbackId")
    func markRolledBackIfPresentFlipsStatusAndKeepsRollbackId() throws {
        let root = try makeWorkspace()
        defer { try? fileManager.removeItem(at: root) }
        let store = makeStore(workingDirectory: root)
        try store.save(makeMetadata(token: "tx", root: root))
        _ = try store.markApplied(token: "tx", rollbackId: "tx")

        let rolledBack = try store.markRolledBackIfPresent(token: "tx")

        #expect(rolledBack?.status == .rolledBack)
        #expect(rolledBack?.rollbackId == "tx")
        #expect(try store.load(token: "tx").status == .rolledBack)
    }

    @Test("markRolledBackIfPresent returns nil for an orphaned bundle without metadata")
    func markRolledBackIfPresentReturnsNilWithoutMetadata() throws {
        let root = try makeWorkspace()
        defer { try? fileManager.removeItem(at: root) }
        let store = makeStore(workingDirectory: root)

        #expect(try store.markRolledBackIfPresent(token: "ghost") == nil)
    }

    @Test("Legacy metadata without the rolledBack case still decodes")
    func legacyMetadataWithoutTheRolledBackCaseStillDecodes() throws {
        let root = try makeWorkspace()
        defer { try? fileManager.removeItem(at: root) }
        let store = makeStore(workingDirectory: root)
        // Hand-written JSON as a pre-unification egg would have serialized it.
        let legacy = """
        {
          "applyToken": "legacy",
          "status": "applied",
          "templateName": "t",
          "workingDirectory": "\(root.path(percentEncoded: false))",
          "outputDirectory": "\(root.path(percentEncoded: false))",
          "workDirectory": "\(root.path(percentEncoded: false))",
          "referenceDirectory": "\(root.path(percentEncoded: false))",
          "changes": [],
          "warnings": [],
          "rollbackId": "legacy"
        }
        """
        try fileManager.createDirectory(at: store.directory(for: "legacy"), withIntermediateDirectories: true)
        try fileManager.writeText(legacy, at: store.metadataURL(for: "legacy"))

        #expect(try store.load(token: "legacy").status == .applied)
    }

    @Test("tokens lists every transaction directory, tolerating a missing root")
    func tokensListsEveryTransactionDirectory() throws {
        let root = try makeWorkspace()
        defer { try? fileManager.removeItem(at: root) }
        let store = makeStore(workingDirectory: root)

        #expect(store.tokens() == [])

        try store.save(makeMetadata(token: "b-tx", root: root))
        try store.save(makeMetadata(token: "a-tx", root: root))
        // A directory with no metadata.json (corrupt/orphan shell) still counts.
        try fileManager.createDirectory(at: store.directory(for: "c-shell"), withIntermediateDirectories: true)
        // A stray file at the root is not a transaction.
        try fileManager.writeText("noise", at: store.root.appending(path: "noise.txt"))

        #expect(store.tokens().sorted() == ["a-tx", "b-tx", "c-shell"])
    }
}
