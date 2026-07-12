import FileManagerProtocol
import Foundation
import Yams

/// Reads and writes egg-lock.yml next to its manifest.
package struct LockfileStore {
    private let fileManager: any FileManagerProtocol

    package init(fileManager: some FileManagerProtocol = FileManager.default) {
        self.fileManager = fileManager
    }

    /// Loads the lockfile at the given path.
    ///
    /// - Returns: The decoded lockfile, or `nil` when none exists yet
    ///   (the first sync creates it — not an error).
    /// - Throws: `LockfileError.decodingFailed` for unreadable content
    package func load(lockfilePath: URL) throws -> Lockfile? {
        guard fileManager.exists(lockfilePath) else {
            return nil
        }

        let data = try fileManager.readFile(at: lockfilePath)
        do {
            return try YAMLDecoder().decode(Lockfile.self, from: data)
        } catch {
            throw LockfileError.decodingFailed(
                path: lockfilePath.path(percentEncoded: false),
                underlying: error,
            )
        }
    }

    /// Writes the lockfile with entries sorted by url and keys sorted,
    /// so repeated writes produce stable diffs.
    package func save(_ lockfile: Lockfile, to lockfilePath: URL) throws {
        let sorted = Lockfile(
            version: lockfile.version,
            templates: lockfile.templates.sorted { $0.url < $1.url },
        )
        let encoder = YAMLEncoder()
        encoder.options.sortKeys = true
        let yaml = try encoder.encode(sorted)
        try fileManager.writeText(yaml, at: lockfilePath)
    }
}

/// Errors that can occur when loading an egg-lock.yml.
package enum LockfileError: Error, LocalizedError, Equatable {
    case decodingFailed(path: String, underlying: Error)

    package var errorDescription: String? {
        switch self {
        case let .decodingFailed(path, underlying):
            "Failed to decode egg-lock.yml at \(path): \(ConfigDecodingErrorFormatter.message(for: underlying))"
        }
    }

    package static func == (lhs: LockfileError, rhs: LockfileError) -> Bool {
        switch (lhs, rhs) {
        case let (.decodingFailed(lhsPath, _), .decodingFailed(rhsPath, _)):
            lhsPath == rhsPath
        }
    }
}
