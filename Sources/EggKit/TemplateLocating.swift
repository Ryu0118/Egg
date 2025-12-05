import Foundation
import Path

struct TemplateLocation: TemplateLocating {
    let projectDirectory: AbsolutePath
    let homeDirectory: AbsolutePath
}

protocol TemplateLocating {
    var projectDirectory: AbsolutePath { get }
    var homeDirectory: AbsolutePath { get }

    init(projectDirectory: AbsolutePath, homeDirectory: AbsolutePath)
}

extension TemplateLocating {
    var projectTemplatesDirectory: AbsolutePath {
        eggsDir(based: projectDirectory)
    }

    var globalTemplatesDirectory: AbsolutePath {
        eggsDir(based: homeDirectory)
    }

    func template(_ name: String, type: TemplateLocationType) -> AbsolutePath {
        switch type {
        case .global:
            globalTemplatesDirectory.appending(component: name)
        case .project:
            projectTemplatesDirectory.appending(component: name)
        }
    }

    func templateDir(for type: TemplateLocationType) -> AbsolutePath {
        switch type {
        case .global:
            globalTemplatesDirectory
        case .project:
            projectTemplatesDirectory
        }
    }

    func eggsDir(based baseURL: AbsolutePath) -> AbsolutePath {
        baseURL.appending(component: ".eggs")
    }
}
