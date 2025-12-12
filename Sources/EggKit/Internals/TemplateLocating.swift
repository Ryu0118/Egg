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
        }
    }

    func templateDir(for type: TemplateLocationType) -> URL {
        switch type {
        case .global:
            globalTemplatesDirectory
        case let .project(projectDirectory, _):
            projectTemplatesDirectory(projectDirectory)
        }
    }

    func eggsDir(based baseURL: URL) -> URL {
        baseURL.appending(component: ".eggs")
    }
}
