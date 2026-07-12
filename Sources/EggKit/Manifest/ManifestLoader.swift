import FileManagerProtocol
import Foundation
import Yams

/// Loads and decodes eggs.yml template manifests.
package struct ManifestLoader {
    private let fileManager: any FileManagerProtocol

    package init(fileManager: some FileManagerProtocol = FileManager.default) {
        self.fileManager = fileManager
    }

    /// Loads a Manifest from the specified eggs.yml path.
    ///
    /// - Parameter manifestPath: The path to the eggs.yml file
    /// - Returns: The decoded and validated Manifest
    /// - Throws: `ManifestLoaderError` if the file is not found, cannot be
    ///   decoded, or contains an invalid entry
    package func load(manifestPath: URL) throws -> Manifest {
        guard fileManager.exists(manifestPath) else {
            throw ManifestLoaderError.manifestNotFound(path: manifestPath.path(percentEncoded: false))
        }

        let data = try fileManager.readFile(at: manifestPath)
        let yamlString = String(decoding: data, as: UTF8.self)

        do {
            // A comment-only or whitespace-only file composes to no node,
            // which cannot back a keyed container; treat it as an empty
            // manifest. Malformed YAML still throws into the catch below.
            guard let node = try Yams.compose(yaml: yamlString) else {
                return Manifest(templates: [])
            }
            let raw = try YAMLDecoder().decode(RawManifest.self, from: node)
            return try Manifest(templates: raw.templates.map(ManifestEntry.make(from:)))
        } catch let error as ManifestLoaderError {
            // Entry-rule violations from ManifestEntry.make must surface as
            // invalidEntry, not get re-wrapped as decodingFailed.
            throw error
        } catch {
            throw ManifestLoaderError.decodingFailed(
                path: manifestPath.path(percentEncoded: false),
                underlying: error,
            )
        }
    }
}

/// Errors that can occur when loading an eggs.yml manifest.
package enum ManifestLoaderError: Error, LocalizedError, Equatable {
    case manifestNotFound(path: String)
    case decodingFailed(path: String, underlying: Error)
    case invalidEntry(url: String, reason: String)

    package var errorDescription: String? {
        switch self {
        case let .manifestNotFound(path):
            "eggs.yml not found at path: \(path)"
        case let .decodingFailed(path, underlying):
            "Failed to decode eggs.yml at \(path): \(ConfigDecodingErrorFormatter.message(for: underlying))"
        case let .invalidEntry(url, reason):
            "Invalid entry '\(url)' in eggs.yml: \(reason)"
        }
    }

    package static func == (lhs: ManifestLoaderError, rhs: ManifestLoaderError) -> Bool {
        switch (lhs, rhs) {
        case let (.manifestNotFound(lhsPath), .manifestNotFound(rhsPath)):
            lhsPath == rhsPath
        case let (.decodingFailed(lhsPath, _), .decodingFailed(rhsPath, _)):
            lhsPath == rhsPath
        case let (.invalidEntry(lhsURL, lhsReason), .invalidEntry(rhsURL, rhsReason)):
            lhsURL == rhsURL && lhsReason == rhsReason
        default:
            false
        }
    }
}
