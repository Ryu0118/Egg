import FileManagerProtocol
import Foundation

struct HatchTransactionStore {
    private let fileManager: any FileManagerProtocol
    private let workingDirectory: URL

    init(fileManager: some FileManagerProtocol, workingDirectory: URL) {
        self.fileManager = fileManager
        self.workingDirectory = workingDirectory
    }

    var root: URL {
        workingDirectory.appending(path: ".egg/transactions")
    }

    /// The directory for a given transaction token, e.g. for
    /// ``TransactionLock`` to lock without duplicating path-joining logic.
    func directory(for token: String) -> URL {
        root.appending(path: token)
    }

    func createDirectory(for token: String) throws -> URL {
        let directory = directory(for: token)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func metadataURL(for token: String) -> URL {
        directory(for: token).appending(path: "metadata.json")
    }

    func save(_ metadata: HatchTransactionMetadata) throws {
        let metadataURL = metadataURL(for: metadata.applyToken)
        let parent = metadataURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(metadata)
        // Atomic (temp-file-then-rename): a reader's load() must never observe
        // a torn/partial write, even outside the lock (e.g. a status check).
        try data.write(to: metadataURL, options: .atomic)
    }

    func load(token: String) throws -> HatchTransactionMetadata {
        let data = try fileManager.readFile(at: metadataURL(for: token))
        return try JSONDecoder().decode(HatchTransactionMetadata.self, from: data)
    }

    func markApplied(token: String, rollbackId: String?) throws -> HatchTransactionMetadata {
        var metadata = try load(token: token)
        metadata.status = .applied
        metadata.rollbackId = rollbackId
        try save(metadata)
        return metadata
    }

    /// Marks a transaction rolled back, keeping its `rollbackId` (the bundle
    /// stays on disk until a later apply replaces it or discard deletes it).
    ///
    /// Returns nil without error when no metadata exists — an orphaned
    /// rollback bundle left by a pre-unification egg version whose discard
    /// removed the transaction directory but not the bundle.
    func markRolledBackIfPresent(token: String) throws -> HatchTransactionMetadata? {
        guard fileManager.exists(metadataURL(for: token)) else { return nil }
        var metadata = try load(token: token)
        metadata.status = .rolledBack
        try save(metadata)
        return metadata
    }

    func metadataExists(token: String) -> Bool {
        fileManager.exists(metadataURL(for: token))
    }

    /// Tokens of every transaction directory under `.egg/transactions`,
    /// including ones whose metadata.json is corrupt or missing. Missing
    /// root yields an empty list.
    func tokens() -> [String] {
        let contents = (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [])) ?? []
        return contents
            .filter { fileManager.isDirectory(at: $0) }
            .map(\.lastPathComponent)
            .sorted()
    }

    func discard(token: String) throws {
        try fileManager.removeIfExists(root.appending(path: token))
    }
}

struct HatchTransactionMetadata: Codable, Equatable {
    enum Status: String, Codable {
        case preview
        case applied
        case rolledBack
        case discarded
    }

    let applyToken: String
    var status: Status
    let templateName: String
    let workingDirectory: String
    let outputDirectory: String
    let workDirectory: String
    let referenceDirectory: String
    let changes: [StoredChangeEntry]
    let warnings: [AgentTransactionWarning]
    var rollbackId: String?

    var changeSummary: ChangeSummary {
        ChangeSummary(
            added: changes.filter { $0.kind == "add" }.map(\.path),
            modified: changes.filter { $0.kind == "modify" }.map(\.path),
            deleted: changes.filter { $0.kind == "delete" }.map(\.path),
        )
    }
}

struct StoredChangeEntry: Codable, Equatable {
    let path: String
    let kind: String

    init(path: String, kind: String) {
        self.path = path
        self.kind = kind
    }

    init(_ entry: AgentChangeEntry) {
        path = entry.path
        kind = entry.kind
    }

    var agentEntry: AgentChangeEntry {
        AgentChangeEntry(path: path, kind: kind)
    }
}
