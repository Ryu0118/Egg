import FileSystem
import Foundation
import Noora
import Path
import Yams

struct TemplatesFinder {
    private let fileSystem: any FileSysteming
    private let location: any TemplateLocating
    private let projectDirectory: AbsolutePath
    private let workingDirectory: AbsolutePath
    private let noora: any Noorable

    private let validator = ConfigValidator()
    private let decoder = YAMLDecoder()

    init(
        fileSystem: some FileSysteming,
        projectDirectory: AbsolutePath,
        workingDirectory: AbsolutePath,
        homeDirectory: AbsolutePath,
        noora: some Noorable = Noora()
    ) {
        self.fileSystem = fileSystem
        self.projectDirectory = projectDirectory
        self.workingDirectory = workingDirectory
        self.noora = noora
        location = TemplateLocation(
            homeDirectory: homeDirectory
        )
    }

    func exists(_ name: String) async throws -> Bool {
        try await validTemplateDirectory(name) != nil
    }

    func fetchTemplate(_ name: String) async throws -> Template {
        guard let templateDir = try await validTemplateDirectory(name) else {
            throw Error.noTemplatesFound(name: name)
        }

        return try await fetchTemplate(templateDir: templateDir)
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

            guard (try? await fileSystem.exists(configPath)) ?? false else {
                continue
            }

            let data = try await fileSystem.readFile(at: configPath)

            do {
                let config = try decoder.decode(Config.self, from: data)
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

    func listWithLocations(emitValidationErrorLog: Bool = true) async throws -> [TemplateWithLocation] {
        let globalTemplates = try await list(for: .global, emitValidationErrorLog: emitValidationErrorLog)
        let projectTemplates = try await list(
            for: .project(
                projectDirectory,
                workingDirectory: workingDirectory
            ),
            emitValidationErrorLog: emitValidationErrorLog
        )

        let globalOptions = globalTemplates.map { TemplateWithLocation(template: $0, location: .global) }
        let projectOptions = projectTemplates.map {
            TemplateWithLocation(
                template: $0,
                location: .project(
                    projectDirectory,
                    workingDirectory: workingDirectory
                )
            )
        }

        return globalOptions + projectOptions
    }

    private func fetchTemplate(
        templateDir: AbsolutePath
    ) async throws -> Template {
        let configPath = templateDir.appending(component: "config.yml")

        let data = try await fileSystem.readFile(at: configPath)
        let config = try decoder.decode(Config.self, from: data)
        try await validator.validate(config)
        return Template(path: templateDir, config: config, isValid: true)
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
        error: any Swift.Error,
        emitValidationErrorLog: Bool
    ) {
        guard emitValidationErrorLog else {
            return
        }

        noora.error(
            """
            \(configPath.pathString) is not a valid configuration.
            \(error.localizedDescription)
            """
        )
    }

    enum Error: LocalizedError {
        case noTemplatesFound(name: String)

        var errorDescription: String? {
            switch self {
            case let .noTemplatesFound(name):
                "Template '\(name)' was not found in global or project templates."
            }
        }
    }
}
