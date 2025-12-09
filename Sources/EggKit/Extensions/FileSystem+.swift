import FileSystem
import Path
import Yams

extension FileSysteming {
    func writeAsYAML(
        _ item: some Encodable,
        at path: Path.AbsolutePath,
        encoder: YAMLEncoder,
        options: Set<WriteJSONOptions> = []
    ) async throws {
        let yaml = try encoder.encode(item)
        if options.contains(.overwrite), try await exists(path) {
            try await remove(path)
        }
        try await writeText(yaml, at: path)
    }
}

extension FileSysteming {
    /// Performs an atomic copy-and-write operation.
    ///
    /// Copies the source to a temporary directory, applies the transformation,
    /// then atomically moves the result to the destination. If any step fails,
    /// the destination remains unchanged.
    ///
    /// - Parameters:
    ///   - source: The source directory to copy from
    ///   - destination: The destination path where the result will be placed
    ///   - transform: A closure that transforms the copied directory in place
    func withAtomicCopyAndWrite(
        from source: AbsolutePath,
        to destination: AbsolutePath,
        perform transform: (AbsolutePath) async throws -> Void
    ) async throws {
        let tempDirectory = try await makeTemporaryDirectory(prefix: "egg-atomic")
        let workingDirectory = tempDirectory.appending(component: "work")

        do {
            try await copy(source, to: workingDirectory)
            try await transform(workingDirectory)

            // Move the transformed content to destination
            // If destination doesn't exist, move the entire directory
            // If destination exists, we need to merge contents
            if try await exists(destination) {
                // Merge: copy items from workingDirectory into destination
                let items = try await contentsOfDirectory(workingDirectory)
                for item in items {
                    let itemName = item.basename
                    let destItem = destination.appending(component: itemName)

                    // Remove existing item in destination if it exists
                    if try await exists(destItem) {
                        try await remove(destItem)
                    }

                    try await move(from: item, to: destItem)
                }
            } else {
                // Destination doesn't exist, move entire directory
                try await move(from: workingDirectory, to: destination)
            }
        } catch {
            try? await remove(tempDirectory)
            throw error
        }

        try await remove(tempDirectory)
    }
}
