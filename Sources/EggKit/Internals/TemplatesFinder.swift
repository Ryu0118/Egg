import FileManagerProtocol
import Foundation
import Noora
import Yams

struct TemplatesFinder {
    private let fileManager: any FileManagerProtocol
    private let location: any TemplateLocating
    private let projectDirectory: URL
    private let workingDirectory: URL
    private let noora: any Noorable
    private let additionalSearchPaths: [URL]

    private let validator = ConfigValidator()
    private let decoder = YAMLDecoder()

    init(
        fileManager: some FileManagerProtocol,
        projectDirectory: URL,
        workingDirectory: URL,
        homeDirectory: URL,
        additionalSearchPaths: [URL] = [],
        noora: some Noorable = Noora()
    ) {
        self.fileManager = fileManager
        self.projectDirectory = projectDirectory
        self.workingDirectory = workingDirectory
        self.additionalSearchPaths = additionalSearchPaths
        self.noora = noora
        location = TemplateLocation(
            homeDirectory: homeDirectory
        )
    }

    func exists(_ name: String) -> Bool {
        (try? validTemplateDirectory(name)) != nil
    }

    func fetchTemplate(_ name: String) async throws -> Template {
        // First, try to find by config.yml name
        if let template = try await findTemplateByConfigName(name) {
            return template
        }

        // Fallback to directory name for backwards compatibility
        guard let templateDir = try validTemplateDirectory(name) else {
            throw Error.noTemplatesFound(name: name)
        }

        return try await fetchTemplate(templateDir: templateDir)
    }

    /// Finds a template by its config.yml name
    private func findTemplateByConfigName(_ name: String) async throws -> Template? {
        let templates = try await listAll(emitValidationErrorLog: false)

        // Find template where config.name matches (custom paths have priority)
        guard let template = templates.all.first(where: { $0.config.name == name }) else {
            return nil
        }

        // Re-fetch with validation
        return try await fetchTemplate(templateDir: template.path)
    }

    func listAll(emitValidationErrorLog: Bool = true) async throws -> Templates {
        // Collect templates from custom search paths (in order)
        var customTemplates: [Template] = []
        for path in additionalSearchPaths {
            let templates = try await list(
                for: .custom(path),
                emitValidationErrorLog: emitValidationErrorLog
            )
            customTemplates.append(contentsOf: templates)
        }

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
        return Templates(custom: customTemplates, global: global, project: project)
    }

    func list(
        for locationType: TemplateLocationType,
        emitValidationErrorLog: Bool = true
    ) async throws -> [Template] {
        let templateDir = location.templateDir(for: locationType)

        var templates = [Template]()

        let templateDirURLs = try? fileManager.contentsOfDirectory(at: templateDir, includingPropertiesForKeys: nil, options: [])

        for templateDirURL in templateDirURLs ?? [] {
            let configPath = templateDirURL.appendingPathComponent("config.yml")

            guard fileManager.exists(configPath) else {
                continue
            }

            let data = try fileManager.readFile(at: configPath)

            do {
                let config = try decoder.decode(Config.self, from: data)
                let template = await convertConfigToTemplate(
                    config,
                    templateDir: templateDirURL,
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

    func validTemplateDirectory(_ name: String) throws -> URL? {
        // Check additional search paths first (in order, highest priority)
        for path in additionalSearchPaths {
            let templateInCustom = location.template(name, type: .custom(path))
            if fileManager.exists(templateInCustom) {
                return templateInCustom
            }
        }

        // Then check global and project locations
        let templateInGlobal = location.template(name, type: .global)
        let templateInProject = location.template(
            name,
            type: .project(
                projectDirectory,
                workingDirectory: workingDirectory
            )
        )

        let existsInGlobal = fileManager.exists(templateInGlobal)
        let existsInProject = fileManager.exists(templateInProject)

        return if existsInGlobal {
            templateInGlobal
        } else if existsInProject {
            templateInProject
        } else {
            nil
        }
    }

    func listWithLocations(emitValidationErrorLog: Bool = true) async throws -> [TemplateWithLocation] {
        // Collect templates from custom search paths first (highest priority)
        var customOptions: [TemplateWithLocation] = []
        for path in additionalSearchPaths {
            let templates = try await list(for: .custom(path), emitValidationErrorLog: emitValidationErrorLog)
            let options = templates.map { TemplateWithLocation(template: $0, location: .custom(path)) }
            customOptions.append(contentsOf: options)
        }

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

        return customOptions + globalOptions + projectOptions
    }

    private func fetchTemplate(
        templateDir: URL
    ) async throws -> Template {
        let configPath = templateDir.appendingPathComponent("config.yml")

        let data = try fileManager.readFile(at: configPath)
        let config = try decoder.decode(Config.self, from: data)
        try await validator.validate(config)
        return Template(path: templateDir, config: config, isValid: true)
    }

    private func convertConfigToTemplate(
        _ config: Config,
        templateDir: URL,
        configPath: URL,
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
        configPath: URL,
        error: any Swift.Error,
        emitValidationErrorLog: Bool
    ) {
        guard emitValidationErrorLog else {
            return
        }

        noora.error(
            """
            \(configPath.path) is not a valid configuration.
            \(error.localizedDescription)
            """
        )
    }

    enum Error: LocalizedError {
        case noTemplatesFound(name: String)

        var errorDescription: String? {
            switch self {
            case let .noTemplatesFound(name):
                "Template '\(name)' was not found in any search paths (custom, global, or project)."
            }
        }
    }
}
