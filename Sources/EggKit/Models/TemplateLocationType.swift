import Foundation
import Noora

package enum TemplateLocationType: Codable, CustomStringConvertible, Equatable {
    case global
    case project(_ projectDirectory: URL, workingDirectory: URL)
    case custom(_ path: URL)

    package var name: String {
        switch self {
        case .global:
            "global"
        case .project:
            "project"
        case .custom:
            "custom"
        }
    }

    package var description: String {
        switch self {
        case .global:
            "Create globally (\(dir))"
        case .project:
            "Create in project (\(dir))"
        case .custom:
            "Custom (\(dir))"
        }
    }

    package var dir: String {
        switch self {
        case .global:
            return "~/.egg"
        case let .project(projectDirectory, workingDirectory):
            let relativePath = projectDirectory.relativePath(from: workingDirectory)
            return relativePath + "/.eggs"
        case let .custom(path):
            return path.path(percentEncoded: false)
        }
    }

    package func updatingProjectDirectory(
        _ projectDirectory: URL,
        workingDirectory: URL,
    ) -> Self? {
        if case .project = self {
            return .project(projectDirectory, workingDirectory: workingDirectory)
        }
        return nil
    }

    /// Returns true if this location type represents a custom search path
    package var isCustom: Bool {
        if case .custom = self {
            return true
        }
        return false
    }
}

package extension TemplateLocationType {
    enum Kind: String, Codable {
        case global
        case project

        package func toConcreteType(
            _ projectDirectory: URL,
            workingDirectory: URL,
        ) -> TemplateLocationType {
            switch self {
            case .global:
                .global
            case .project:
                .project(projectDirectory, workingDirectory: workingDirectory)
            }
        }
    }
}
