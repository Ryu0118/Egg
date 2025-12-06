import Foundation
import Path
import FileSystem
import Yams
import Noora

struct TemplatesFinder {
    private let fileSystem: any FileSysteming
    private let location: any TemplateLocating
    private let projectDirectory: AbsolutePath
    private let workingDirectory: AbsolutePath

    private let validator = ConfigValidator()

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

    func listAll(emitValidationErrorLog: Bool = true) async throws -> Templates {
        let global = try await list(
            for: .global,
            emitValidationErrorLog: emitValidationErrorLog
        )
        let project = try await list(
            for: .project(
                projectDirectory,
                workingDirectory: workingDirectory
            ),
            emitValidationErrorLog: emitValidationErrorLog
        )
        return Templates(global: global, project: project)
    }

    func list(
        for locationType: TemplateLocationType,
        emitValidationErrorLog: Bool = true
    ) async throws -> [Template] {
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
                    configPath: configPath,
                    emitValidationErrorLog: emitValidationErrorLog
                )
                templates.append(template)
            } catch {
                validationErrorLog(configPath: configPath, error: error, emitValidationErrorLog: emitValidationErrorLog)
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
        configPath: AbsolutePath,
        emitValidationErrorLog: Bool
    ) async -> Template {
        do {
            try await validator.validate(config)

            return Template(path: templateDir, config: config, isValid: true)
        } catch {
            validationErrorLog(
                configPath: configPath,
                error: error,
                emitValidationErrorLog: emitValidationErrorLog
            )
            return Template(path: templateDir, config: config, isValid: false)
        }
    }

    private func validationErrorLog(
        configPath: AbsolutePath,
        error: any Error,
        emitValidationErrorLog: Bool
    ) {
        guard emitValidationErrorLog else {
            return
        }

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
