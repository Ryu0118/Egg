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
    /// Removes the item at the provided path only if it exists.
    ///
    /// This helper avoids scattering existence checks throughout the codebase and
    /// keeps file removal call sites concise.
    ///
    /// - Parameter path: Path to remove if present
    func removeIfExists(_ path: AbsolutePath) async throws {
        if try await exists(path) {
            try await remove(path)
        }
    }
}

extension FileSysteming {
    /// Copies a file or directory if it exists at the source path.
    ///
    /// Creates parent directories at the destination if needed.
    /// If the destination already exists, it is removed before copying.
    ///
    /// - Parameters:
    ///   - source: The source path to copy from
    ///   - destination: The destination path to copy to
    /// - Returns: `true` if the copy was performed, `false` if source doesn't exist
    func copyIfExists(from source: AbsolutePath, to destination: AbsolutePath) async throws -> Bool {
        guard try await exists(source) else {
            return false
        }

        let parent = destination.parentDirectory
        try await makeDirectory(at: parent, options: [.createTargetParentDirectories])
        if try await exists(destination) {
            try await remove(destination)
        }

        try await copy(source, to: destination)
        return true
    }

    func withTemporaryDirectory<T>(
        prefix: String,
        _ action: (AbsolutePath) async throws -> T
    ) async throws -> T {
        var temporaryDirectory: AbsolutePath! = nil
        var result: Result<T, Error>!
        do {
            temporaryDirectory = try await makeTemporaryDirectory(prefix: prefix)
            result = .success(try await action(temporaryDirectory))
        } catch {
            result = .failure(error)
        }
        if let temporaryDirectory {
            try await remove(temporaryDirectory)
        }
        switch result! {
        case let .success(value): return value
        case let .failure(error): throw error
        }
    }

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
