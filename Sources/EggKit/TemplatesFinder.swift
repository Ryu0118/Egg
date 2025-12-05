import Foundation
import Path
import FileSystem
import Yams

struct TemplatesFinder {
    let fileSystem: any FileSysteming
    let location: any TemplateLocating
    let projectDirectory: AbsolutePath
    let workingDirectory: AbsolutePath

    init(
        fileSystem: some FileSysteming,
        projectDirectory: AbsolutePath,
        workingDirectory: AbsolutePath,
        homeDirectory: AbsolutePath
    ) {
        self.fileSystem = fileSystem
        self.projectDirectory = projectDirectory
        self.workingDirectory = workingDirectory
        self.location = TemplateLocation(
            projectDirectory: projectDirectory,
            homeDirectory: homeDirectory
        )
    }

    func exists(_ name: String) async throws -> Bool {
        try await validTemplateDirectory(name) != nil
    }

    func listAll() async throws -> Templates {
        let global = try await list(for: .global)
        let project = try await list(for: .project(projectDirectory.relative(to: workingDirectory)))
        return Templates(global: global, project: project)
    }

    func list(for locationType: TemplateLocationType) async throws -> [Template] {
        let templateDir = location.templateDir(for: locationType)
        let validator = ConfigValidator()

        var templates = [Template]()

        let templateDirs = try? await fileSystem.contentsOfDirectory(templateDir)

        for templateDir in templateDirs ?? [] {
            let configPath = templateDir.appending(component: "config.yml")
            guard (try? await self.fileSystem.exists(configPath)) ?? false else {
                continue
            }
            let data = try await self.fileSystem.readFile(at: configPath)
            let config = try YAMLDecoder().decode(Config.self, from: data)
            try await validator.validate(config)
            templates.append(Template(path: templateDir, config: config))
        }

        return templates
    }

    func validTemplateDirectory(_ name: String) async throws -> AbsolutePath? {
        let templateInGlobal = location.template(name, type: .global)
        let templateInProject = location.template(name, type: .project(projectDirectory.relative(to: workingDirectory)))

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
