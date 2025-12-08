import ArgumentParser
import EggKit
import FileSystem
import Foundation
import Path

package protocol HasProjectDirectory {
    var projectDirectory: String? { get }
    static var fileSystem: FileSystem { get }
}

package extension HasProjectDirectory {
    func resolveProjectDirectory() async throws -> AbsolutePath {
        if let projectDirectory {
            try await AbsolutePath(validating: projectDirectory, relativeTo: Self.fileSystem.currentWorkingDirectory())
        } else {
            try await Self.fileSystem.currentWorkingDirectory()
        }
    }
}

package extension AbsolutePath {
    init?(validating: String?) throws {
        guard let validating else {
            return nil
        }
        try self.init(validating: validating)
    }
}

extension TemplateLocationType.Kind: ExpressibleByArgument {}
