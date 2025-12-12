import Foundation
import Noora

package enum TemplateLocationType: Codable, CustomStringConvertible, Equatable {
    case global
    case project(_ projectDirectory: URL, workingDirectory: URL)

    package var name: String {
        switch self {
        case .global:
            "global"
        case .project:
            "project"
        }
    }

    package var description: String {
        switch self {
        case .global:
            "Create globally (\(dir))"
        case .project:
            "Create in project (\(dir))"
        }
    }

    package var dir: String {
        switch self {
        case .global:
            return "~/.egg"
        case let .project(projectDirectory, workingDirectory):
            let relativePath = projectDirectory.relativePath(from: workingDirectory)
            return relativePath + "/.eggs"
        }
    }

    package func updatingProjectDirectory(
        _ projectDirectory: URL,
        workingDirectory: URL
    ) -> Self? {
        if case .project = self {
            return .project(projectDirectory, workingDirectory: workingDirectory)
        }
        return nil
    }
}

package extension TemplateLocationType {
    enum Kind: String, Codable, Sendable {
        case global
        case project

        package func toConcreteType(
            _ projectDirectory: URL,
            workingDirectory: URL
        ) -> TemplateLocationType {
            return switch self {
            case .global:
                .global
            case .project:
                .project(projectDirectory, workingDirectory: workingDirectory)
            }
        }
    }
}
