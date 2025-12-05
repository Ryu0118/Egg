import Foundation
import Path
import FileSystem
import Yams
import AsyncOperations

actor TemplatesFinder {
    nonisolated(unsafe) let fileSystem: any FileSysteming
    let location: any TemplateLocating
    let projectDirectory: AbsolutePath

    nonisolated(nonsending) init(
        fileSystem: some FileSysteming,
        projectDirectory: AbsolutePath,
        homeDirectory: AbsolutePath
    ) async {
        self.fileSystem = fileSystem
        self.projectDirectory = projectDirectory
        self.location = TemplateLocation(
            projectDirectory: projectDirectory,
            homeDirectory: homeDirectory
        )
    }

    func exists(_ name: String) async throws -> Bool {
        try await validTemplateDirectory(name) != nil
    }

    func listAll() async throws -> Templates {
        async let global = list(for: .global)
        async let project = list(for: .project(projectDirectory))
        return try await Templates(global: global, project: project)
    }

    func list(for locationType: TemplateLocationType) async throws -> [Template] {
        let numberOfConcurrentTasks: UInt = 10
        let templateDir = location.templateDir(for: locationType)
        let validator = ConfigValidator()

        return try await fileSystem.contentsOfDirectory(templateDir)
            .lazy
            .filter { !URL(filePath: $0.pathString).isFileURL }
            .asyncFilter(numberOfConcurrentTasks: numberOfConcurrentTasks) { path in
                try await self.fileSystem.exists(path.appending(component: "config.yml"))
            }
            .asyncCompactMap(numberOfConcurrentTasks: numberOfConcurrentTasks) { path -> Template? in
                do {
                    let data = try await self.fileSystem.readFile(at: path)
                    let config = try YAMLDecoder().decode(Config.self, from: data)
                    try await validator.validate(config)
                    return Template(path: path, config: config)
                } catch {
                    return nil
                }
            }
    }

    func validTemplateDirectory(_ name: String) async throws -> AbsolutePath? {
        let templateInGlobal = location.template(name, type: .global)
        let templateInProject = location.template(name, type: .project(projectDirectory))

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

struct Templates {
    let global: [Template]
    let project: [Template]
}

struct Template {
    let path: AbsolutePath
    let config: Config
}
