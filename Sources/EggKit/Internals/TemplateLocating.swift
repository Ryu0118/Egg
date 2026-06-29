import Foundation

struct TemplateLocation: TemplateLocating {
    let homeDirectory: URL
}

protocol TemplateLocating {
    var homeDirectory: URL { get }

    init(homeDirectory: URL)
}

extension TemplateLocating {
    func projectTemplatesDirectory(_ projectDirectory: URL) -> URL {
        eggsDir(based: projectDirectory)
    }

    var globalTemplatesDirectory: URL {
        eggsDir(based: homeDirectory)
    }

    func template(_ name: String, type: TemplateLocationType) -> URL {
        switch type {
        case .global:
            globalTemplatesDirectory.appending(component: name)
        case let .project(projectDirectory, _):
            projectTemplatesDirectory(projectDirectory).appending(component: name)
        case let .custom(path):
            path.appending(component: name)
        }
    }

    func templateDir(for type: TemplateLocationType) -> URL {
        switch type {
        case .global:
            globalTemplatesDirectory
        case let .project(projectDirectory, _):
            projectTemplatesDirectory(projectDirectory)
        case let .custom(path):
            path
        }
    }

    func eggsDir(based baseURL: URL) -> URL {
        baseURL.appending(component: ".eggs")
    }

    /// Determines the location type of a template based on its path.
    ///
    /// - Parameters:
    ///   - templateName: The name of the template
    ///   - templatePath: The resolved path to the template
    ///   - additionalSearchPaths: Custom search paths to check first
    ///   - projectDirectory: The project directory for project-local templates
    ///   - workingDirectory: The working directory
    /// - Returns: The location type where the template was found
    func determineLocation(
        templateName: String,
        templatePath: URL,
        additionalSearchPaths: [URL],
        projectDirectory: URL,
        workingDirectory: URL,
    ) -> TemplateLocationType {
        // Check custom paths first (highest priority)
        for customPath in additionalSearchPaths {
            let customTemplatePath = template(templateName, type: .custom(customPath))
            if templatePath == customTemplatePath {
                return .custom(customPath)
            }
        }

        // Check global path
        let globalPath = template(templateName, type: .global)
        if templatePath == globalPath {
            return .global
        }

        // Default to project
        return .project(projectDirectory, workingDirectory: workingDirectory)
    }
}
