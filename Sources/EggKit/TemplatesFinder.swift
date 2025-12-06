import Foundation
import Path
import FileSystem
import Yams
import Noora

struct TemplatesFinder {
    let fileSystem: any FileSysteming
    let location: any TemplateLocating
    let projectDirectory: AbsolutePath
    let workingDirectory: AbsolutePath

    let validator = ConfigValidator()

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
            homeDirectory: homeDirectory
        )
    }

    func exists(_ name: String) async throws -> Bool {
        try await validTemplateDirectory(name) != nil
    }

    func listAll() async throws -> Templates {
        let global = try await list(for: .global)
        let project = try await list(
            for: .project(
                projectDirectory,
                workingDirectory: workingDirectory
            )
        )
        return Templates(global: global, project: project)
    }

    func list(for locationType: TemplateLocationType) async throws -> [Template] {
        let templateDir = location.templateDir(for: locationType)

        var templates = [Template]()

        let templateDirs = try? await fileSystem.contentsOfDirectory(templateDir)

        for templateDir in templateDirs ?? [] {
            let configPath = templateDir.appending(component: "config.yml")

            guard (try? await self.fileSystem.exists(configPath)) ?? false else {
                continue
            }

            let data = try await self.fileSystem.readFile(at: configPath)

            do {
                let config = try YAMLDecoder().decode(Config.self, from: data)
                let template = await convertConfigToTemplate(
                    config,
                    templateDir: templateDir,
                    configPath: configPath
                )
                templates.append(template)
            } catch {
                validationErrorLog(configPath: configPath, error: error)
            }
        }

        return templates
    }

    func validTemplateDirectory(_ name: String) async throws -> AbsolutePath? {
        let templateInGlobal = location.template(name, type: .global)
        let templateInProject = location.template(
            name,
            type: .project(
                projectDirectory,
                workingDirectory: workingDirectory
            )
        )

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

    private func convertConfigToTemplate(
        _ config: Config,
        templateDir: AbsolutePath,
        configPath: AbsolutePath
    ) async -> Template {
        do {
            try await validator.validate(config)

            return Template(path: templateDir, config: config, isValid: true)
        } catch {
            validationErrorLog(configPath: configPath, error: error)
            return Template(path: templateDir, config: config, isValid: false)
        }
    }

    private func validationErrorLog(configPath: AbsolutePath, error: any Error) {
        Noora().error(
            """
            \(configPath.pathString) is not a valid configuration. 
            \(error.localizedDescription)
            """
        )
    }
}

struct Templates {
    let global: [Template]
    let project: [Template]
}

struct Template: Equatable {
    let path: AbsolutePath
    let config: Config
    let isValid: Bool
}
