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

extension TemplateLocationType.Kind: ExpressibleByArgument {}
