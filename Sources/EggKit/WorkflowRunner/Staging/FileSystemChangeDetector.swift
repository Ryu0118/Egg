import FileManagerProtocol
import Foundation

struct FileSystemChangeDetector {
    private let fileManager: any FileManagerProtocol
    private let excludedDirectoryNames: Set<String>

    init(
        fileManager: some FileManagerProtocol,
        excludedDirectoryNames: Set<String> = Self.defaultExcludedDirectoryNames,
    ) {
        self.fileManager = fileManager
        self.excludedDirectoryNames = excludedDirectoryNames
    }

    func computeChanges(referenceRoot: URL, changedRoot: URL) throws -> ChangeSummary {
        let referenceFiles = try enumerateFiles(in: referenceRoot)
        let changedFiles = try enumerateFiles(in: changedRoot)

        let referencePaths = Set(referenceFiles.keys)
        let changedPaths = Set(changedFiles.keys)

        let added = changedPaths.subtracting(referencePaths).sorted()
        let deleted = referencePaths.subtracting(changedPaths).sorted()
        let modified = try referencePaths.intersection(changedPaths)
            .filter { path in
                try fileContents(referenceFiles[path]!) != fileContents(changedFiles[path]!)
            }
            .sorted()

        return ChangeSummary(added: added, modified: modified, deleted: deleted)
    }

    func computeChanges(
        referenceRoot: URL,
        changedRoot: URL,
        limitingTo paths: [String],
    ) throws -> ChangeSummary {
        let all = try computeChanges(referenceRoot: referenceRoot, changedRoot: changedRoot)
        let pathSet = Set(paths)
        return ChangeSummary(
            added: all.added.filter { pathSet.contains($0) },
            modified: all.modified.filter { pathSet.contains($0) },
            deleted: all.deleted.filter { pathSet.contains($0) },
        )
    }

    private func enumerateFiles(in root: URL) throws -> [String: URL] {
        guard fileManager.exists(root) else {
            return [:]
        }

        var result: [String: URL] = [:]
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [],
            errorHandler: nil,
        ) else {
            return result
        }

        while let item = enumerator.nextObject() as? URL {
            if shouldSkip(item, relativeTo: root) {
                if fileManager.isDirectory(at: item) {
                    enumerator.skipDescendants()
                }
                continue
            }

            guard !fileManager.isDirectory(at: item) else {
                continue
            }

            result[item.relativePath(from: root)] = item
        }

        return result
    }

    private func shouldSkip(_ item: URL, relativeTo root: URL) -> Bool {
        let relativePath = item.relativePath(from: root)
        let components = relativePath.split(separator: "/").map(String.init)
        return components.contains { excludedDirectoryNames.contains($0) }
    }

    private func fileContents(_ url: URL) throws -> Data {
        try fileManager.readFile(at: url)
    }
}

extension FileSystemChangeDetector {
    static let defaultExcludedDirectoryNames: Set<String> = [
        ".git",
        ".egg",
        "node_modules",
        ".build",
        ".swiftpm",
        "DerivedData",
        ".venv",
        "venv",
        "dist",
        ".cache",
        ".next",
        ".turbo",
    ]
}
