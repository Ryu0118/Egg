@testable import EggKit
import FileManagerProtocol
import Foundation
import Testing

@Suite("Transactions listing surfaces every record, including corrupt and orphaned ones")
struct AgentHatchTransactionsListTests {
    private let fileManager: some FileManagerProtocol = FileManager.default

    private func makeWorkspace() throws -> URL {
        try fileManager.makeTemporaryDirectory(prefix: "AgentHatchTransactionsListTests")
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

    private func writeTransaction(token: String, in root: URL, status: HatchTransactionMetadata.Status, templateName: String = "t") throws {
        let store = makeStore(workingDirectory: root)
        let directory = try store.createDirectory(for: token)
        try fileManager.createDirectory(at: directory.appending(path: "work"), withIntermediateDirectories: true)
        try fileManager.writeText("payload", at: directory.appending(path: "work/file.txt"))
        try store.save(HatchTransactionMetadata(
            applyToken: token,
            status: status,
            templateName: templateName,
            workingDirectory: root.path(percentEncoded: false),
            outputDirectory: root.path(percentEncoded: false),
            workDirectory: directory.appending(path: "work").path(percentEncoded: false),
            referenceDirectory: directory.appending(path: "reference").path(percentEncoded: false),
            changes: [],
            warnings: [],
            rollbackId: status == .preview ? nil : token,
        ))
    }

    private func writeBundle(id: String, in root: URL, status: String = "applied") throws {
        let bundleRoot = root.appending(path: ".egg/rollback/\(id)")
        try fileManager.createDirectory(at: bundleRoot.appending(path: "before"), withIntermediateDirectories: true)
        let manifest = """
        {
          "id": "\(id)",
          "applyToken": "\(id)",
          "templateName": "orphan-template",
          "workingDirectory": "\(root.path(percentEncoded: false))",
          "status": "\(status)",
          "changes": []
        }
        """
        try fileManager.writeText(manifest, at: bundleRoot.appending(path: "manifest.json"))
    }

    @Test("Lists entries with status, template name, bundle presence, and size, sorted by token")
    func listsEntriesWithStatusTemplateNameBundlePresenceAndSize() throws {
        let root = try makeWorkspace()
        defer { try? fileManager.removeItem(at: root) }
        try writeTransaction(token: "b-applied", in: root, status: .applied)
        try writeBundle(id: "b-applied", in: root)
        try writeTransaction(token: "a-preview", in: root, status: .preview)
        try writeTransaction(token: "c-rolled", in: root, status: .rolledBack)
        try writeBundle(id: "c-rolled", in: root, status: "rolledBack")

        let result = makeRunner(workingDirectory: root).transactions()

        #expect(result.status == "ok")
        #expect(result.transactions.map(\.token) == ["a-preview", "b-applied", "c-rolled"])
        #expect(result.transactions.map(\.status) == [.preview, .applied, .rolledBack])
        #expect(result.transactions.map(\.hasRollbackBundle) == [false, true, true])
        #expect(result.transactions.allSatisfy { $0.templateName == "t" })
        #expect(result.transactions.allSatisfy { $0.sizeBytes > 0 })
    }

    @Test("Corrupt metadata surfaces as corrupt without failing the listing")
    func corruptMetadataSurfacesAsCorrupt() throws {
        let root = try makeWorkspace()
        defer { try? fileManager.removeItem(at: root) }
        let store = makeStore(workingDirectory: root)
        _ = try store.createDirectory(for: "bad")
        try fileManager.writeText("not json", at: store.metadataURL(for: "bad"))
        try writeTransaction(token: "good", in: root, status: .preview)

        let result = makeRunner(workingDirectory: root).transactions()

        #expect(result.transactions.map(\.token) == ["bad", "good"])
        let bad = result.transactions[0]
        #expect(bad.status == .corrupt)
        #expect(bad.templateName == nil)
    }

    @Test("A rollback bundle without a transaction directory lists as orphanedRollback")
    func aBundleWithoutATransactionDirectoryListsAsOrphaned() throws {
        let root = try makeWorkspace()
        defer { try? fileManager.removeItem(at: root) }
        try writeBundle(id: "orphan", in: root)

        let result = makeRunner(workingDirectory: root).transactions()

        #expect(result.transactions.count == 1)
        let entry = try #require(result.transactions.first)
        #expect(entry.status == .orphanedRollback)
        #expect(entry.templateName == "orphan-template")
        #expect(entry.hasRollbackBundle)
    }

    @Test("A missing .egg directory yields an empty listing")
    func aMissingEggDirectoryYieldsAnEmptyListing() throws {
        let root = try makeWorkspace()
        defer { try? fileManager.removeItem(at: root) }

        let result = makeRunner(workingDirectory: root).transactions()

        #expect(result.transactions.isEmpty)
    }
}
