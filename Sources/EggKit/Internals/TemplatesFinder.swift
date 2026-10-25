import FileManagerProtocol
import Foundation
import Interaction
import Yams

struct TemplatesFinder {
    private let fileManager: any FileManagerProtocol
    private let location: any TemplateLocating
    private let projectDirectory: URL
    private let workingDirectory: URL
    private let interaction: any InteractionProviding
    private let additionalSearchPaths: [URL]

    private let validator = ConfigValidator()
    private let decoder = YAMLDecoder()

    init(
        fileManager: some FileManagerProtocol,
        projectDirectory: URL,
        workingDirectory: URL,
        homeDirectory: URL,
        additionalSearchPaths: [URL] = [],
        interaction: some InteractionProviding = GuardedTerminal(),
    ) {
        self.fileManager = fileManager
        self.projectDirectory = projectDirectory
        self.workingDirectory = workingDirectory
        self.additionalSearchPaths = additionalSearchPaths
        self.interaction = interaction
        location = TemplateLocation(
            homeDirectory: homeDirectory,
        )
    }

    func exists(_ name: String) async -> Bool {
        await (try? validTemplateDirectory(name)) != nil
    }

    /// Resolves a template by config.yml name, then by directory name.
    ///
    /// - Parameter location: When non-`nil`, only that location is searched
    ///   (custom search paths are skipped). When `nil`, locations are searched
    ///   in priority order: custom paths, project, global.
    func fetchTemplate(_ name: String, location: TemplateLocationType? = nil) async throws -> Template {
        // First, try to find by config.yml name
        if let template = try await findTemplateByConfigName(name, location: location) {
            return template
        }

        // Fallback to directory name for backwards compatibility
        guard let templateDir = try await validTemplateDirectory(name, location: location) else {
            throw Error.noTemplatesFound(name: name)
        }

        return try await fetchTemplate(templateDir: templateDir)
    }

    func listAll(emitValidationErrorLog: Bool = true) async throws -> Templates {
        // Collect templates from custom search paths (in order)
        var customTemplates: [Template] = []
        for path in additionalSearchPaths {
            let templates = try await list(
                for: .custom(path),
                emitValidationErrorLog: emitValidationErrorLog,
            )
            customTemplates.append(contentsOf: templates)
        }

        let global = try await list(
            for: .global,
            emitValidationErrorLog: emitValidationErrorLog,
        )
        let project = try await list(
            for: .project(
                projectDirectory,
                workingDirectory: workingDirectory,
            ),
            emitValidationErrorLog: emitValidationErrorLog,
        )
        return Templates(custom: customTemplates, global: global, project: project)
    }

    func list(
        for locationType: TemplateLocationType,
        emitValidationErrorLog: Bool = true,
    ) async throws -> [Template] {
        let templateDir = location.templateDir(for: locationType)

        var templates = [Template]()

        let candidateDirectories = candidateTemplateDirectories(at: templateDir)

        for templateDirURL in candidateDirectories {
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
                    emitValidationErrorLog: emitValidationErrorLog,
                )
                templates.append(template)
            } catch {
                validationErrorLog(configPath: configPath, error: error, emitValidationErrorLog: emitValidationErrorLog)
            }
        }

        return templates
    }

    /// - Parameter globalBeforeProject: Search global before project when no
    ///   `location` is given. Only `template move` sets this, to keep its
    ///   existing rule that the global template is the move source when both
    ///   locations hold one.
    func validTemplateDirectory(
        _ name: String,
        location restriction: TemplateLocationType? = nil,
        globalBeforeProject: Bool = false,
    ) async throws -> URL? {
        // A template name becomes a path component (global/.eggs/<name>,
        // project/.eggs/<name>, or a custom search path's own <name>).
        // URL.appending(component:) does not sanitize '/' or '..', so an
        // unvalidated name here is a path-traversal vector — every lookup
        // path (CLI Delete/Move/Duplicate, MCP Detail/Delete/Move/Duplicate,
        // hatch's template resolution) funnels through this function, so
        // this single check protects all of them. Reuses the same rule new
        // template names are already validated against.
        guard await ValidationRule.directoryName(error: "")(name) == nil else {
            throw Error.invalidTemplateName(name: name)
        }

        for candidate in searchOrder(restrictedTo: restriction, globalBeforeProject: globalBeforeProject) {
            switch candidate {
            case let .custom(path):
                if let customTemplate = resolveCustomTemplateDirectory(name, in: path) {
                    return customTemplate
                }
            case .global, .project:
                // existsAsLink, not exists: a dangling symlink sitting exactly
                // at the candidate path must still be treated as "occupied"
                // (e.g. so 'create' correctly refuses to create over it).
                let candidateDir = location.template(name, type: candidate)
                if fileManager.existsAsLink(candidateDir) {
                    return candidateDir
                }
            }
        }

        return nil
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
                workingDirectory: workingDirectory,
            ),
            emitValidationErrorLog: emitValidationErrorLog,
        )

        let globalOptions = globalTemplates.map { TemplateWithLocation(template: $0, location: .global) }
        let projectOptions = projectTemplates.map {
            TemplateWithLocation(
                template: $0,
                location: .project(
                    projectDirectory,
                    workingDirectory: workingDirectory,
                ),
            )
        }

        return customOptions + globalOptions + projectOptions
    }

    /// Finds a template by its config.yml name
    private func findTemplateByConfigName(_ name: String, location restriction: TemplateLocationType?) async throws -> Template? {
        for candidate in searchOrder(restrictedTo: restriction) {
            let templates = try await list(for: candidate, emitValidationErrorLog: false)
            if let template = templates.first(where: { $0.config.name == name }) {
                // Re-fetch with validation
                return try await fetchTemplate(templateDir: template.path)
            }
        }
        return nil
    }

    /// Locations to search, highest priority first: custom search paths in
    /// declared order, then project, then global. A project template must
    /// shadow a global one of the same name. A `restriction` narrows the
    /// search to that single location.
    private func searchOrder(
        restrictedTo restriction: TemplateLocationType?,
        globalBeforeProject: Bool = false,
    ) -> [TemplateLocationType] {
        if let restriction {
            return [restriction]
        }
        let project = TemplateLocationType.project(projectDirectory, workingDirectory: workingDirectory)
        return additionalSearchPaths.map { .custom($0) }
            + (globalBeforeProject ? [.global, project] : [project, .global])
    }

    /// Returns the directories that should be scanned for templates for the given location directory.
    ///
    /// The directory itself is considered a candidate so that custom search paths pointing directly
    /// at a single template still work, while the immediate subdirectories are included to support
    /// directories that contain multiple templates.
    private func candidateTemplateDirectories(at locationDirectory: URL) -> [URL] {
        guard fileManager.isDirectory(at: locationDirectory) else {
            return []
        }

        var directories: [URL] = [locationDirectory]

        if let entries = try? fileManager.contentsOfDirectory(
            at: locationDirectory,
            includingPropertiesForKeys: nil,
            options: [],
        ) {
            for entry in entries where fileManager.isDirectory(at: entry) {
                directories.append(entry)
            }
        }

        return directories
    }

    private func resolveCustomTemplateDirectory(_ name: String, in path: URL) -> URL? {
        let templateInCustom = location.template(name, type: .custom(path))
        if fileManager.existsAsLink(templateInCustom) {
            return templateInCustom
        }

        return templatePathIfMatchesRoot(path, name: name)
    }

    private func templatePathIfMatchesRoot(_ candidate: URL, name: String) -> URL? {
        let configURL = candidate.appendingPathComponent("config.yml")
        guard fileManager.exists(configURL) else {
            return nil
        }

        if candidate.lastPathComponent == name {
            return candidate
        }

        guard let configName = configName(at: configURL) else {
            return nil
        }

        return configName == name ? candidate : nil
    }

    private func configName(at configURL: URL) -> String? {
        do {
            let data = try fileManager.readFile(at: configURL)
            let config = try decoder.decode(Config.self, from: data)
            return config.name
        } catch {
            return nil
        }
    }

    private func fetchTemplate(
        templateDir: URL,
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
        emitValidationErrorLog: Bool,
    ) async -> Template {
        do {
            try await validator.validate(config)

            return Template(path: templateDir, config: config, isValid: true)
        } catch {
            validationErrorLog(
                configPath: configPath,
                error: error,
                emitValidationErrorLog: emitValidationErrorLog,
            )
            return Template(path: templateDir, config: config, isValid: false)
        }
    }

    private func validationErrorLog(
        configPath: URL,
        error: any Swift.Error,
        emitValidationErrorLog: Bool,
    ) {
        guard emitValidationErrorLog else {
            return
        }

        interaction.writeFailure(
            """
            \(configPath.path) is not a valid configuration.
            \(error.localizedDescription)
            """,
        )
    }

    enum Error: LocalizedError {
        case noTemplatesFound(name: String)
        case invalidTemplateName(name: String)

        var errorDescription: String? {
            switch self {
            case let .noTemplatesFound(name):
                "Template '\(name)' was not found in any search paths (custom, project, or global)."
            case let .invalidTemplateName(name):
                "Invalid template name '\(name)': must be a plain directory name, not a path. It cannot contain '/' and cannot be '.' or '..'."
            }
        }
    }
}
