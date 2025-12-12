import Darwin
import Foundation

/// Protocol for directory cloning operations.
///
/// Implementations provide different strategies for cloning directories,
/// such as APFS copy-on-write cloning or traditional copying.
public protocol DirectoryCloning: Sendable {
    /// Clones a directory or file from source to destination.
    ///
    /// - Parameters:
    ///   - source: The source URL to clone from
    ///   - destination: The destination URL to clone to
    /// - Throws: An error if the cloning operation fails
    func clone(from source: URL, to destination: URL) async throws
}

/// APFS-based directory cloner using copy-on-write semantics.
///
/// This implementation uses the `clonefile` system call available on macOS
/// with APFS filesystems. It provides instant cloning regardless of directory
/// size by leveraging copy-on-write (CoW) semantics.
///
/// ## Usage
/// ```swift
/// let cloner = APFSDirectoryCloner()
/// try cloner.clone(from: sourceURL, to: destinationURL)
/// ```
///
/// ## Requirements
/// - macOS with APFS filesystem
/// - Source and destination must be on the same APFS volume for CoW benefits
public struct APFSDirectoryCloner: DirectoryCloning, Sendable {
    public init() {}

    public func clone(from source: URL, to destination: URL) async throws {
        guard source.isFileURL, destination.isFileURL else {
            throw CloningError.invalidURL
        }

        let result = source.withUnsafeFileSystemRepresentation { srcPath in
            destination.withUnsafeFileSystemRepresentation { dstPath in
                guard let srcPath, let dstPath else {
                    return Int32(-1)
                }
                return clonefile(srcPath, dstPath, 0)
            }
        }

        if result != 0 {
            let errorCode = errno
            let errorMessage = String(cString: strerror(errorCode))
            throw CloningError.systemError(code: errorCode, message: errorMessage)
        }
    }
}

/// Errors that can occur during directory cloning operations.
public enum CloningError: Error, Sendable, LocalizedError, Equatable {
    /// The provided URL is not a file URL.
    case invalidURL

    /// A system-level error occurred during the clone operation.
    case systemError(code: Int32, message: String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            "The provided URL is not a valid file URL"
        case let .systemError(code, message):
            "Cloning failed with error code \(code): \(message)"
        }
    }
}
