import ArgumentParser
import EggKit
import FileManagerProtocol
import Foundation

package protocol HasProjectDirectory {
    var projectDirectory: String? { get }
    static var fileManager: any FileManagerProtocol { get }
}

package extension HasProjectDirectory {
    func resolveProjectDirectory() async throws -> URL {
        if let projectDirectory {
            URL(filePath: projectDirectory, relativeTo: URL(filePath: Self.fileManager.currentDirectoryPath))
        } else {
            URL(filePath: Self.fileManager.currentDirectoryPath)
        }
    }
}

package protocol HasTemplateSearchPaths {
    var templateSearchPaths: [String] { get }
    static var fileManager: any FileManagerProtocol { get }
}

package extension HasTemplateSearchPaths {
    func resolveTemplateSearchPaths() -> [URL] {
        templateSearchPaths.map { path in
            URL(filePath: path, relativeTo: URL(filePath: Self.fileManager.currentDirectoryPath))
        }
    }
}

extension TemplateLocationType.Kind: ExpressibleByArgument {}

/// Returns the home directory, respecting the HOME environment variable.
/// This is important for testing purposes where HOME can be set to a temporary directory.
package func resolveHomeDirectory() -> URL {
    if let homePath = ProcessInfo.processInfo.environment["HOME"] {
        return URL(filePath: homePath)
    }
    return FileManager.default.homeDirectoryForCurrentUser
}
