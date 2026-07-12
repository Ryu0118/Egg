import FileManagerProtocol
import Foundation
import Yams

/// Writes eggs.yml template manifests back out.
///
/// Mirrors ``LockfileStore/save(_:to:)``'s pattern: sort for a stable diff,
/// encode with sorted keys, write as text.
package struct ManifestWriter {
    private let fileManager: any FileManagerProtocol

    package init(fileManager: some FileManagerProtocol = FileManager.default) {
        self.fileManager = fileManager
    }

    /// Writes `manifest` to `manifestPath`, creating the parent directory
    /// first if it doesn't exist yet (the global manifest's `~/.config/egg/`
    /// may not exist on a fresh machine).
    package func save(_ manifest: Manifest, to manifestPath: URL) throws {
        let parentDirectory = manifestPath.deletingLastPathComponent()
        if !fileManager.exists(parentDirectory) {
            try fileManager.createDirectory(at: parentDirectory, withIntermediateDirectories: true)
        }

        let encoder = YAMLEncoder()
        encoder.options.sortKeys = true
        let yaml = try encoder.encode(RawManifest(manifest))
        try fileManager.writeText(yaml, at: manifestPath)
    }
}
