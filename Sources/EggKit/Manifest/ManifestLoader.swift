import FileManagerProtocol
import Foundation
import Yams

/// Loads and decodes egg.yml template manifests.
package struct ManifestLoader {
    private let fileManager: any FileManagerProtocol

    package init(fileManager: some FileManagerProtocol = FileManager.default) {
        self.fileManager = fileManager
    }

    /// Loads a Manifest from the specified egg.yml path.
    ///
    /// - Parameter manifestPath: The path to the egg.yml file
    /// - Returns: The decoded and validated Manifest
    /// - Throws: `ManifestLoaderError` if the file is not found, cannot be
    ///   decoded, or contains an invalid entry
    package func load(manifestPath: URL) throws -> Manifest {
        guard fileManager.exists(manifestPath) else {
            throw ManifestLoaderError.manifestNotFound(path: manifestPath.path(percentEncoded: false))
        }

        let data = try fileManager.readFile(at: manifestPath)
        let yamlString = String(decoding: data, as: UTF8.self)

        // A comment-only or whitespace-only file parses as a null document,
        // which cannot back a keyed container; treat it as an empty manifest.
        // Malformed YAML must still surface as decodingFailed.
        do {
            if try Yams.load(yaml: yamlString) == nil {
                return Manifest(templates: [])
            }
        } catch {
            throw ManifestLoaderError.decodingFailed(
                path: manifestPath.path(percentEncoded: false),
                underlying: error,
            )
        }

        let raw: RawManifest
        do {
            raw = try YAMLDecoder().decode(RawManifest.self, from: data)
        } catch {
            throw ManifestLoaderError.decodingFailed(
                path: manifestPath.path(percentEncoded: false),
                underlying: error,
            )
        }

        return try Manifest(templates: raw.templates.map(ManifestEntry.make(from:)))
    }
}

/// Errors that can occur when loading an egg.yml manifest.
package enum ManifestLoaderError: Error, LocalizedError, Equatable {
    case manifestNotFound(path: String)
    case decodingFailed(path: String, underlying: Error)
    case invalidEntry(url: String, reason: String)

    package var errorDescription: String? {
        switch self {
        case let .manifestNotFound(path):
            "egg.yml not found at path: \(path)"
        case let .decodingFailed(path, underlying):
            "Failed to decode egg.yml at \(path): \(ConfigDecodingErrorFormatter.message(for: underlying))"
        case let .invalidEntry(url, reason):
            "Invalid entry '\(url)' in egg.yml: \(reason)"
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
