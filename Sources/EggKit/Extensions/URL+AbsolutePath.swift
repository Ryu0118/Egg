import FileSystem
import Foundation
import Path

package extension URL {
    var absolutePath: AbsolutePath {
        get throws {
            try AbsolutePath(validating: path(percentEncoded: false))
        }
    }
}
