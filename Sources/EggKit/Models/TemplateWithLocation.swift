import Foundation
import Path

package struct TemplateWithLocation: CustomStringConvertible, Equatable {
    let template: Template
    let location: TemplateLocationType

    package var description: String {
        "\(template.config.name) (\(location.name))"
    }
}
