import Foundation
import Noora
import Path

package enum TemplateLocationType: Codable, CaseIterable, CustomStringConvertible, Equatable {
    package typealias RawValue = String

    case global
    case project(_ projectDirectory: AbsolutePath? = nil)

    package init?(rawValue: String) {
        if rawValue == "global" {
            self = .global
        } else if rawValue == "project" {
            self = .project()
        } else {
            return nil
        }
    }

    package var rawValue: String {
        self == .global ? "global" : "project"
    }

    package var name: String {
        switch self {
        case .global:
            "global"
        case .project:
            "project"
        }
    }

    package static var allCases: [Self] {
        [
            .global,
            .project(),
        ]
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
            "~/.eggs/"
        case .project(let projectDirectory):
            if let projectDirectory {
                projectDirectory.appending(component: ".eggs").pathString
            } else {
                "./.eggs/"
            }
        }
    }

    package func updatingProjectDirectory(
        _ projectDirectory: AbsolutePath?
    ) -> Self? {
        if case .project = self {
            return .project(projectDirectory)
        }
        return nil
    }
}
