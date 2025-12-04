import Foundation
import Path
import FileSystem

struct TemplatesFinder {
    let fileSystem: any FileSysteming
    let location: any TemplateLocating

    init(
        fileSystem: any FileSysteming,
        currentDirectory: AbsolutePath,
        homeDirectory: AbsolutePath
    ) {
        self.fileSystem = fileSystem
        self.location = TemplateLocation(
            projectDirectory: currentDirectory,
            homeDirectory: homeDirectory
        )
    }

    func exists(_ name: String) async throws -> Bool {
        try await validTemplateDirectory(name) != nil
    }

    func validTemplateDirectory(_ name: String) async throws -> AbsolutePath? {
        let templateInGlobal = location.template(name, type: .global)
        let templateInProject = location.template(name, type: .project)

        let existsInGlobal = try await fileSystem.exists(templateInGlobal)
        let existsInProject = try await fileSystem.exists(templateInProject)

        return if existsInGlobal {
            templateInGlobal
        } else if existsInProject {
            templateInProject
        } else {
            nil
        }
    }
}
