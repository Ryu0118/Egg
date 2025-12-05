import Foundation
import Path

struct TemplateLocation: TemplateLocating {
    let homeDirectory: AbsolutePath
}

protocol TemplateLocating {
    var homeDirectory: AbsolutePath { get }

    init(homeDirectory: AbsolutePath)
}

extension TemplateLocating {
    func projectTemplatesDirectory(_ projectDirectory: AbsolutePath) -> AbsolutePath {
        eggsDir(based: projectDirectory)
    }

    var globalTemplatesDirectory: AbsolutePath {
        eggsDir(based: homeDirectory)
    }

    func template(_ name: String, type: TemplateLocationType) -> AbsolutePath {
        switch type {
        case .global:
            globalTemplatesDirectory.appending(component: name)
        case .project(let projectDirectory, _):
            projectTemplatesDirectory(projectDirectory).appending(component: name)
        }
    }

    func templateDir(for type: TemplateLocationType) -> AbsolutePath {
        switch type {
        case .global:
            globalTemplatesDirectory
        case .project(let projectDirectory, _):
            projectTemplatesDirectory(projectDirectory)
        }
    }

    func eggsDir(based baseURL: AbsolutePath) -> AbsolutePath {
        baseURL.appending(component: ".eggs")
    }
}
