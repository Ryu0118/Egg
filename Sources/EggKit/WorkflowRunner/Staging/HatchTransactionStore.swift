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

    func createDirectory(for token: String) throws -> URL {
        let directory = root.appending(path: token)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func metadataURL(for token: String) -> URL {
        root.appending(path: token).appending(path: "metadata.json")
    }

    func save(_ metadata: HatchTransactionMetadata) throws {
        let metadataURL = metadataURL(for: metadata.applyToken)
        let parent = metadataURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(metadata)
        try data.write(to: metadataURL)
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

    func discard(token: String) throws {
        try fileManager.removeIfExists(root.appending(path: token))
    }
}

struct HatchTransactionMetadata: Codable, Equatable {
    enum Status: String, Codable {
        case preview
        case applied
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
