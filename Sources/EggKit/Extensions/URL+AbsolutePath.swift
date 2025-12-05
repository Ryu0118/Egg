import Foundation
import FileSystem
import Path

extension URL {
    package var absolutePath: AbsolutePath {
        get throws {
            try AbsolutePath(validating: path(percentEncoded: false))
        }
    }
}
