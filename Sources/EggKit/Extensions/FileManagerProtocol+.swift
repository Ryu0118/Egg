import Darwin
import FileManagerProtocol
import Foundation
import Yams

/// A captured snapshot of a file's POSIX permission bits and extended
/// attributes, taken before it's overwritten, so they can be reapplied to the
/// new content afterward.
///
/// Replacing a file's content (`copyItem`ing fresh content over an existing
/// path) does not carry over the original's mode bits or xattrs — without
/// this, an "apply" that overwrites a tracked file silently downgrades it to
/// default permissions and drops every extended attribute.
struct FileAttributeSnapshot {
    let posixPermissions: NSNumber?
    let extendedAttributes: [(name: String, value: Data)]
}

extension FileManagerProtocol {
    /// Checks if a file or directory exists at the specified URL.
    ///
    /// Follows the final symlink: for a dangling symlink, or a relative
    /// symlink whose target doesn't resolve from wherever `url` currently
    /// sits (e.g. after being copied to a different directory), this reports
    /// `false` even though a link is present at `url`. Use ``existsAsLink(_:)``
    /// when the link's own presence — not its target's — is what matters, such
    /// as before removing or backing up a path that may be a symlink.
    func exists(_ url: URL) -> Bool {
        fileExists(atPath: url.path(percentEncoded: false))
    }

    /// Checks if *something* is present at the specified URL, including a
    /// dangling or unresolvable symbolic link.
    ///
    /// Uses `attributesOfItem`, which resolves via `lstat` rather than
    /// following the final symlink, so it succeeds for a symlink whose target
    /// is missing or doesn't resolve from this location.
    func existsAsLink(_ url: URL) -> Bool {
        (try? attributesOfItem(atPath: url.path(percentEncoded: false))) != nil
    }

    /// Checks if the item at the specified URL is a directory.
    func isDirectory(at url: URL) -> Bool {
        var isDir: ObjCBool = false
        guard fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDir) else {
            return false
        }
        return isDir.boolValue
    }

    /// Checks if the item at the specified URL is itself a symbolic link —
    /// not whether it *points to* one. Resolves via `lstat` (through
    /// `attributesOfItem`), so this is `true` for a dangling symlink whose
    /// target doesn't exist, unlike a `fileExists(atPath:isDirectory:)`-based
    /// check, which would follow the link and report neither file nor
    /// directory for a dangling target.
    func isSymbolicLink(at url: URL) -> Bool {
        (try? attributesOfItem(atPath: url.path(percentEncoded: false)))?[.type] as? FileAttributeType == .typeSymbolicLink
    }

    /// Captures `url`'s POSIX permissions and extended attributes, if it
    /// exists. Best-effort: a missing file or unreadable attribute yields an
    /// empty snapshot rather than throwing — call this before overwriting a
    /// path, then ``restore(_:to:)`` afterward.
    func capturedFileAttributes(at url: URL) -> FileAttributeSnapshot {
        let path = url.path(percentEncoded: false)
        let permissions = (try? attributesOfItem(atPath: path))?[.posixPermissions] as? NSNumber
        return FileAttributeSnapshot(posixPermissions: permissions, extendedAttributes: listExtendedAttributes(atPath: path))
    }

    /// Reapplies a previously captured snapshot to `url`.
    ///
    /// Best-effort: any individual attribute that fails to apply is silently
    /// skipped rather than failing the whole operation — attribute
    /// preservation is a nicety on top of a successful content write, not a
    /// correctness requirement for the write itself.
    func restore(_ snapshot: FileAttributeSnapshot, to url: URL) {
        let path = url.path(percentEncoded: false)
        if let permissions = snapshot.posixPermissions {
            try? setAttributes([.posixPermissions: permissions], ofItemAtPath: path)
        }
        for attribute in snapshot.extendedAttributes {
            attribute.value.withUnsafeBytes { buffer in
                _ = setxattr(path, attribute.name, buffer.baseAddress, buffer.count, 0, XATTR_NOFOLLOW)
            }
        }
    }

    /// Removes the item at the provided URL only if it exists.
    ///
    /// Uses ``existsAsLink(_:)`` rather than ``exists(_:)`` so a dangling
    /// symlink at `url` is removed too — a caller asking to remove whatever is
    /// at this path means the link itself, not its (possibly missing) target.
    func removeIfExists(_ url: URL) throws {
        if existsAsLink(url) {
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

    /// Copies a file, directory, or symlink if it exists at the source URL.
    ///
    /// Creates parent directories at the destination if needed.
    /// If the destination already exists, it is removed before copying.
    ///
    /// Both existence checks use ``existsAsLink(_:)``, not ``exists(_:)``: a
    /// dangling symlink at `source` must still be copied (as a symlink, since
    /// `copyItem` doesn't follow it), and a dangling symlink sitting at
    /// `destination` must still be cleared before the copy lands.
    ///
    /// - Parameters:
    ///   - source: The source URL to copy from
    ///   - destination: The destination URL to copy to
    /// - Returns: `true` if the copy was performed, `false` if source doesn't exist
    func copyIfExists(from source: URL, to destination: URL) throws -> Bool {
        guard existsAsLink(source) else {
            return false
        }

        let parent = destination.deletingLastPathComponent()
        try createDirectory(at: parent, withIntermediateDirectories: true, attributes: nil)
        if existsAsLink(destination) {
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

    /// Lists extended attribute names and values at `path`, using `lstat`-family
    /// syscalls (`XATTR_NOFOLLOW`) so a symlink's own attributes are read
    /// rather than its target's.
    private func listExtendedAttributes(atPath path: String) -> [(name: String, value: Data)] {
        let listSize = listxattr(path, nil, 0, XATTR_NOFOLLOW)
        guard listSize > 0 else { return [] }

        var nameBuffer = [CChar](repeating: 0, count: listSize)
        let actualListSize = listxattr(path, &nameBuffer, listSize, XATTR_NOFOLLOW)
        guard actualListSize > 0 else { return [] }

        let rawNames = nameBuffer[0 ..< actualListSize].map { UInt8(bitPattern: $0) }
        let names = rawNames.split(separator: 0).compactMap { String(bytes: $0, encoding: .utf8) }

        return names.compactMap { name -> (name: String, value: Data)? in
            let valueSize = getxattr(path, name, nil, 0, 0, XATTR_NOFOLLOW)
            guard valueSize > 0 else { return nil }
            var valueBuffer = [UInt8](repeating: 0, count: valueSize)
            let actualValueSize = getxattr(path, name, &valueBuffer, valueSize, 0, XATTR_NOFOLLOW)
            guard actualValueSize > 0 else { return nil }
            return (name, Data(valueBuffer.prefix(actualValueSize)))
        }
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
            // existsAsLink, not exists: a dangling symlink already sitting at
            // destItem (e.g. a git-tracked dangling symlink cloned into the
            // staging tree) must still be recognized as "there" so it gets
            // removed before the new item lands — exists() follows it, finds
            // nothing, and the subsequent moveItem then fails because the path
            // actually is occupied.
            let destExists = existsAsLink(destItem)
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
