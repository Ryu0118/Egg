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
/// - Falls back to a regular copy when source and destination are on different
///   volumes or on a filesystem without clone support
public struct APFSDirectoryCloner: DirectoryCloning, Sendable {
    /// Returns 0 on success or the errno of a failed clonefile(2) call.
    /// Injectable so unit tests can force cross-volume failures (EXDEV)
    /// without a second real volume.
    typealias CloneSyscall = @Sendable (
        _ source: UnsafePointer<CChar>,
        _ destination: UnsafePointer<CChar>,
        _ flags: UInt32,
    ) -> Int32

    private let cloneSyscall: CloneSyscall

    public init() {
        // errno is read inside the closure, synchronously after the failed
        // call, so the thread-local value is still the clonefile failure.
        self.init { src, dst, flags in
            clonefile(src, dst, flags) == 0 ? 0 : errno
        }
    }

    init(cloneSyscall: @escaping CloneSyscall) {
        self.cloneSyscall = cloneSyscall
    }

    public func clone(from source: URL, to destination: URL) async throws {
        guard source.isFileURL, destination.isFileURL else {
            throw CloningError.invalidURL
        }

        let errorCode = source.withUnsafeFileSystemRepresentation { srcPath in
            destination.withUnsafeFileSystemRepresentation { dstPath in
                guard let srcPath, let dstPath else {
                    return EINVAL
                }
                // CLONE_NOFOLLOW preserves symbolic links as-is instead of
                // following them and cloning their targets.
                return cloneSyscall(srcPath, dstPath, UInt32(CLONE_NOFOLLOW))
            }
        }

        switch errorCode {
        case 0:
            return
        case EXDEV, ENOTSUP:
            // clonefile(2) can't cross volumes (EXDEV) or run on non-cloning
            // filesystems (ENOTSUP). copyItem preserves symlinks as links —
            // same semantics as CLONE_NOFOLLOW — and fails on an existing
            // destination just like clonefile, so only the CoW speedup is lost.
            try FileManager.default.copyItem(at: source, to: destination)
        default:
            throw CloningError.systemError(code: errorCode, message: String(cString: strerror(errorCode)))
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
