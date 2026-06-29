import FileManagerProtocol
import Foundation
import Yams

extension FileManagerProtocol {
    /// Checks if a file or directory exists at the specified URL.
    func exists(_ url: URL) -> Bool {
        fileExists(atPath: url.path(percentEncoded: false))
    }

    /// Checks if the item at the specified URL is a directory.
    func isDirectory(at url: URL) -> Bool {
        var isDir: ObjCBool = false
        guard fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDir) else {
            return false
        }
        return isDir.boolValue
    }

    /// Removes the item at the provided URL only if it exists.
    func removeIfExists(_ url: URL) throws {
        if exists(url) {
            try removeItem(at: url)
        }
    }

    /// Reads the contents of a file at the specified URL.
    func readFile(at url: URL) throws -> Data {
        guard let data = contents(atPath: url.path(percentEncoded: false)) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        return data
    }

    /// Writes text to a file at the specified URL.
    func writeText(_ text: String, at url: URL, encoding: String.Encoding = .utf8) throws {
        let data = text.data(using: encoding) ?? Data()
        try data.write(to: url)
    }

    /// Copies a file or directory if it exists at the source URL.
    ///
    /// Creates parent directories at the destination if needed.
    /// If the destination already exists, it is removed before copying.
    ///
    /// - Parameters:
    ///   - source: The source URL to copy from
    ///   - destination: The destination URL to copy to
    /// - Returns: `true` if the copy was performed, `false` if source doesn't exist
    func copyIfExists(from source: URL, to destination: URL) throws -> Bool {
        guard exists(source) else {
            return false
        }

        let parent = destination.deletingLastPathComponent()
        try createDirectory(at: parent, withIntermediateDirectories: true, attributes: nil)
        if exists(destination) {
            try removeItem(at: destination)
        }

        try copyItem(at: source, to: destination)
        return true
    }

    /// Performs an atomic copy-and-write operation with async transformation.
    ///
    /// Copies the source to a temporary directory, applies the async transformation,
    /// then atomically moves the result to the destination. If any step fails,
    /// the destination remains unchanged.
    ///
    /// When merging with an existing destination:
    /// - Files are replaced (existing file removed, new file moved in)
    /// - Directories are merged recursively (contents combined, not replaced)
    ///
    /// - Parameters:
    ///   - source: The source directory to copy from
    ///   - destination: The destination URL where the result will be placed
    ///   - transform: An async closure that transforms the copied directory in place
    func withAtomicCopyAndWrite(
        from source: URL,
        to destination: URL,
        perform transform: (URL) async throws -> Void,
    ) async throws {
        let tempDirectory = try makeTemporaryDirectory(prefix: "egg-atomic")
        let workingDirectory = tempDirectory.appendingPathComponent("work")

        do {
            try copyItem(at: source, to: workingDirectory)
            try await transform(workingDirectory)

            // Move the transformed content to destination
            // If destination doesn't exist, move the entire directory
            // If destination exists, we need to merge contents recursively
            if exists(destination) {
                try mergeDirectory(from: workingDirectory, to: destination)
            } else {
                let parentDirectory = destination.deletingLastPathComponent()
                if !exists(parentDirectory) {
                    try createDirectory(at: parentDirectory, withIntermediateDirectories: true, attributes: nil)
                }
                try moveItem(at: workingDirectory, to: destination)
            }
        } catch {
            try? removeItem(at: tempDirectory)
            throw error
        }

        try removeItem(at: tempDirectory)
    }

    /// Recursively merges the source directory into the destination.
    ///
    /// - Files: Replace existing files with source files
    /// - Directories: Recursively merge contents (don't replace entire directory)
    ///
    /// This preserves existing files in destination directories that don't exist in source.
    private func mergeDirectory(
        from source: URL,
        to destination: URL,
    ) throws {
        let items = try contentsOfDirectory(at: source, includingPropertiesForKeys: nil, options: [])

        for itemURL in items {
            let itemName = itemURL.lastPathComponent
            let destItem = destination.appendingPathComponent(itemName)

            let sourceIsDirectory = isDirectory(at: itemURL)
            let destExists = exists(destItem)
            let destIsDirectory = destExists ? isDirectory(at: destItem) : false

            if sourceIsDirectory {
                if destIsDirectory {
                    // Both are directories: recursively merge
                    try mergeDirectory(from: itemURL, to: destItem)
                } else {
                    // Source is directory, destination is file (or doesn't exist)
                    // Remove file if exists, create directory, and recursively merge
                    if destExists {
                        try removeItem(at: destItem)
                    }
                    try createDirectory(at: destItem, withIntermediateDirectories: false, attributes: nil)
                    try mergeDirectory(from: itemURL, to: destItem)
                }
            } else {
                // Source is a file: replace destination
                if destExists {
                    try removeItem(at: destItem)
                }
                try moveItem(at: itemURL, to: destItem)
            }
        }
    }
}

extension FileManagerProtocol {
    func writeAsYAML(
        _ item: some Encodable,
        at url: URL,
        encoder: YAMLEncoder,
    ) throws {
        let yaml = try encoder.encode(item)
        if exists(url) {
            try removeItem(at: url)
        }
        try writeText(yaml, at: url)
    }
}
