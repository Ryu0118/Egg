@testable import EggKit
import FileManagerProtocol
import Foundation
import Testing

/// Unit tests for the symlink-aware existence checks and attribute
/// preservation primitives added in ``FileManagerProtocol+``.
///
/// These are the root-cause fixes behind a set of rollback/apply bugs found
/// by edge-case testing: `exists(_:)` follows symlinks, which made a dangling
/// (or relocated-relative) symlink look "missing" everywhere that mattered —
/// rollback's "add" removal, its missing-backup precheck, the staging clone's
/// file filter, and the atomic-copy merge step. Full end-to-end behavior
/// (git-tracked dangling symlinks, template symlinks, mode/xattr round-trips
/// through preview→apply→rollback) was verified against the real `egg`
/// binary; these tests protect the primitives those fixes are built on.
@Suite("FileManagerProtocol symlink and attribute preservation")
struct FileManagerProtocolSymlinkAndAttributeTests {
    private let fileManager: some FileManagerProtocol = FileManager.default

    private func makeWorkspace() throws -> URL {
        try fileManager.makeTemporaryDirectory(prefix: "FileManagerProtocolSymlinkTests")
    }

    // MARK: - existsAsLink / isSymbolicLink

    @Test("existsAsLink is true for a dangling symlink; exists is false")
    func existsAsLinkIsTrueForADanglingSymlinkExistsIsFalse() throws {
        let root = try makeWorkspace()
        defer { try? fileManager.removeItem(at: root) }

        let link = root.appending(path: "dangling")
        try fileManager.createSymbolicLink(at: link, withDestinationURL: root.appending(path: "does-not-exist"))

        #expect(fileManager.exists(link) == false)
        #expect(fileManager.existsAsLink(link) == true)
        #expect(fileManager.isSymbolicLink(at: link) == true)
    }

    @Test("existsAsLink is true for a valid symlink; isSymbolicLink is true, isDirectory follows to the target")
    func existsAsLinkIsTrueForAValidSymlinkIsSymbolicLinkIsTrueIsDirectoryFollowsToTheTarget() throws {
        let root = try makeWorkspace()
        defer { try? fileManager.removeItem(at: root) }

        let targetDir = root.appending(path: "targetDir")
        try fileManager.createDirectory(at: targetDir, withIntermediateDirectories: true)
        let link = root.appending(path: "link")
        try fileManager.createSymbolicLink(at: link, withDestinationURL: targetDir)

        #expect(fileManager.exists(link) == true)
        #expect(fileManager.existsAsLink(link) == true)
        #expect(fileManager.isSymbolicLink(at: link) == true)
        // isDirectory follows the link to its target, unlike isSymbolicLink.
        #expect(fileManager.isDirectory(at: link) == true)
    }

    @Test("existsAsLink and exists agree for a regular file and a missing path")
    func existsAsLinkAndExistsAgreeForARegularFileAndAMissingPath() throws {
        let root = try makeWorkspace()
        defer { try? fileManager.removeItem(at: root) }

        let file = root.appending(path: "file.txt")
        try fileManager.writeText("hi\n", at: file)
        #expect(fileManager.exists(file) == true)
        #expect(fileManager.existsAsLink(file) == true)
        #expect(fileManager.isSymbolicLink(at: file) == false)

        let missing = root.appending(path: "missing.txt")
        #expect(fileManager.exists(missing) == false)
        #expect(fileManager.existsAsLink(missing) == false)
    }

    // MARK: - removeIfExists

    @Test("removeIfExists removes a dangling symlink")
    func removeIfExistsRemovesADanglingSymlink() throws {
        let root = try makeWorkspace()
        defer { try? fileManager.removeItem(at: root) }

        let link = root.appending(path: "dangling")
        try fileManager.createSymbolicLink(at: link, withDestinationURL: root.appending(path: "gone"))
        #expect(fileManager.existsAsLink(link))

        try fileManager.removeIfExists(link)
        #expect(!fileManager.existsAsLink(link))
    }

    // MARK: - copyIfExists

    @Test("copyIfExists copies a dangling symlink as a symlink, preserving its (unresolved) target string")
    func copyIfExistsCopiesADanglingSymlinkAsASymlinkPreservingItsUnresolvedTargetString() throws {
        let root = try makeWorkspace()
        defer { try? fileManager.removeItem(at: root) }

        let source = root.appending(path: "source-link")
        try fileManager.createSymbolicLink(atPath: source.path(percentEncoded: false), withDestinationPath: "nowhere.txt")

        let destination = root.appending(path: "nested/dest-link")
        let copied = try fileManager.copyIfExists(from: source, to: destination)

        #expect(copied == true)
        #expect(fileManager.isSymbolicLink(at: destination) == true)
        #expect(try fileManager.destinationOfSymbolicLink(atPath: destination.path(percentEncoded: false)) == "nowhere.txt")
    }

    @Test("copyIfExists clears a dangling symlink already sitting at the destination")
    func copyIfExistsClearsADanglingSymlinkAlreadySittingAtTheDestination() throws {
        let root = try makeWorkspace()
        defer { try? fileManager.removeItem(at: root) }

        let source = root.appending(path: "source.txt")
        try fileManager.writeText("new content\n", at: source)

        let destination = root.appending(path: "dest.txt")
        try fileManager.createSymbolicLink(atPath: destination.path(percentEncoded: false), withDestinationPath: "nowhere.txt")

        let copied = try fileManager.copyIfExists(from: source, to: destination)
        #expect(copied == true)
        #expect(fileManager.isSymbolicLink(at: destination) == false)
        #expect(try String(decoding: fileManager.readFile(at: destination), as: UTF8.self) == "new content\n")
    }

    // MARK: - capturedFileAttributes / restore

    @Test("Captures and restores POSIX permission bits across a content overwrite")
    func capturesAndRestoresPOSIXPermissionBitsAcrossAContentOverwrite() throws {
        let root = try makeWorkspace()
        defer { try? fileManager.removeItem(at: root) }

        let file = root.appending(path: "perms.txt")
        try fileManager.writeText("old\n", at: file)
        try fileManager.setAttributes([.posixPermissions: 0o640], ofItemAtPath: file.path(percentEncoded: false))

        let snapshot = fileManager.capturedFileAttributes(at: file)

        // Simulate a content overwrite that resets permissions to a default.
        try fileManager.removeItem(at: file)
        try fileManager.writeText("new\n", at: file)
        try fileManager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path(percentEncoded: false))

        fileManager.restore(snapshot, to: file)

        let mode = try fileManager.attributesOfItem(atPath: file.path(percentEncoded: false))[.posixPermissions] as? NSNumber
        #expect(mode?.uint16Value == 0o640)
    }

    @Test("Captures and restores an extended attribute across a content overwrite")
    func capturesAndRestoresAnExtendedAttributeAcrossAContentOverwrite() throws {
        let root = try makeWorkspace()
        defer { try? fileManager.removeItem(at: root) }

        let file = root.appending(path: "tagged.txt")
        try fileManager.writeText("old\n", at: file)
        let path = file.path(percentEncoded: false)
        let value = Array("hello".utf8)
        #expect(setxattr(path, "com.egg.test", value, value.count, 0, XATTR_NOFOLLOW) == 0)

        let snapshot = fileManager.capturedFileAttributes(at: file)
        #expect(snapshot.extendedAttributes.contains { $0.name == "com.egg.test" })

        // Simulate a content overwrite that drops extended attributes.
        try fileManager.removeItem(at: file)
        try fileManager.writeText("new\n", at: file)
        #expect(getxattr(path, "com.egg.test", nil, 0, 0, XATTR_NOFOLLOW) < 0)

        fileManager.restore(snapshot, to: file)

        var buffer = [UInt8](repeating: 0, count: 16)
        let size = getxattr(path, "com.egg.test", &buffer, buffer.count, 0, XATTR_NOFOLLOW)
        #expect(size == 5)
        #expect(String(bytes: buffer.prefix(size), encoding: .utf8) == "hello")
    }

    @Test("capturedFileAttributes on a missing path yields an empty, harmless snapshot")
    func capturedFileAttributesOnAMissingPathYieldsAnEmptyHarmlessSnapshot() throws {
        let root = try makeWorkspace()
        defer { try? fileManager.removeItem(at: root) }

        let snapshot = fileManager.capturedFileAttributes(at: root.appending(path: "missing.txt"))
        #expect(snapshot.posixPermissions == nil)
        #expect(snapshot.extendedAttributes.isEmpty)

        // restore() with an empty snapshot must not throw or fail silently in
        // a way that breaks the caller.
        let file = root.appending(path: "file.txt")
        try fileManager.writeText("x\n", at: file)
        fileManager.restore(snapshot, to: file)
        #expect(try String(decoding: fileManager.readFile(at: file), as: UTF8.self) == "x\n")
    }
}
