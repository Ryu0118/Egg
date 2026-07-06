@testable import EggKit
import FileManagerProtocol
import Foundation
import Testing

/// The cloner enumerates what staging copies. egg's own `.egg/` records are
/// untracked and their `transactions/*/work` trees are git repos of their
/// own, so before the structural exclusion every preview re-cloned all prior
/// previews' records — two user files compounded into millions of staged
/// files within a handful of previews.
@Suite("GitTrackedDirectoryCloner excludes egg's own bookkeeping")
struct GitTrackedDirectoryClonerTests {
    private let fileManager: some FileManagerProtocol = FileManager.default

    @Test(".egg/ never appears in the cloneable set nor in the clone itself")
    func eggBookkeepingIsExcluded() async throws {
        let root = try fileManager.makeTemporaryDirectory(prefix: "ClonerEggExclusion")
        defer { try? fileManager.removeItem(at: root) }
        let source = root.appending(path: "src")
        try fileManager.createDirectory(at: source, withIntermediateDirectories: true)
        try fileManager.writeText("real\n", at: source.appending(path: "real.txt"))
        try fileManager.createDirectory(at: source.appending(path: ".egg/transactions/tok"), withIntermediateDirectories: true)
        try fileManager.writeText("{}", at: source.appending(path: ".egg/transactions/tok/metadata.json"))
        try initializeGitRepository(at: source)

        let cloner = GitTrackedDirectoryCloner(fileManager: fileManager)

        let files = try await cloner.cloneableFiles(in: source)
        #expect(files.contains("real.txt"))
        #expect(!files.contains { $0.hasPrefix(".egg") })

        let destination = root.appending(path: "dst")
        try await cloner.clone(from: source, to: destination)
        #expect(fileManager.exists(destination.appending(path: "real.txt")))
        #expect(!fileManager.exists(destination.appending(path: ".egg")))
    }

    private func initializeGitRepository(at directory: URL) throws {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/git")
        process.arguments = ["init", "--quiet"]
        process.currentDirectoryURL = directory
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            struct GitInitFailed: Error {}
            throw GitInitFailed()
        }
    }
}
