import Foundation
import Noora
import Path

package enum TemplateLocationType: Codable, CustomStringConvertible, Equatable {
    case global
    case project(_ projectDirectory: AbsolutePath, workingDirectory: AbsolutePath)

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
            "~/.egg"
        case .project(let projectDirectory, let workingDirectory):
            projectDirectory
                .relative(to: workingDirectory)
                .appending(component: ".eggs").pathString
        }
    }

    package func updatingProjectDirectory(
        _ projectDirectory: AbsolutePath,
        workingDirectory: AbsolutePath
    ) -> Self? {
        if case .project = self {
            return .project(projectDirectory, workingDirectory: workingDirectory)
        }
        return nil
    }
}

extension TemplateLocationType {
    package enum Meta: String, Codable {
        case global
        case project

        package func toConcreteType(
            _ projectDirectory: AbsolutePath,
            workingDirectory: AbsolutePath
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
