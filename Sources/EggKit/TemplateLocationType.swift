import Foundation
import Noora

package enum TemplateLocationType: String, Codable, CaseIterable, CustomStringConvertible {
    case global
    case project

    package var description: String {
        switch self {
        case .global:
            "Create globally (~/.eggs/)"
        case .project:
            "Create in project (./.eggs/)"
        }
    }
}
