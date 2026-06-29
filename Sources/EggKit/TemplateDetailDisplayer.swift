import Foundation
import Noora

/// Displays formatted template details to the console
struct TemplateDetailDisplayer {
    private let noora: any Noorable
    private let formatter = TemplateDetailFormatter()

    init(noora: some Noorable = Noora()) {
        self.noora = noora
    }

    func display(template: Template, location: TemplateLocationType) {
        let detail = formatter.format(template: template, location: location)
        let separator = String(repeating: "─", count: 60)

        displayHeader(detail: detail, separator: separator)
        displayBasicInfo(detail: detail)
        displayMacros(detail: detail, separator: separator)
        displayExampleCommand(detail: detail, separator: separator)
    }

    private func displayHeader(
        detail: TemplateDetailFormatter.FormattedDetail,
        separator: String,
    ) {
        noora.passthrough("\(.muted(separator))\n", tab: 0)
        noora.passthrough("\(.accent(detail.basicInfo.name))\n", tab: 1)
        noora.passthrough("\(.muted(separator))\n", tab: 0)
    }

    private func displayBasicInfo(detail: TemplateDetailFormatter.FormattedDetail) {
        noora.passthrough("Description:  \(detail.basicInfo.description)\n", tab: 1)

        if let version = detail.basicInfo.version {
            noora.passthrough("Version:      \(version)\n", tab: 1)
        }

        noora.passthrough("Location:     \(detail.basicInfo.locationName) (\(detail.basicInfo.locationDir))\n", tab: 1)
        noora.passthrough("Path:         \(detail.basicInfo.path)\n", tab: 1)
        noora.passthrough("\n")
    }

    private func displayMacros(
        detail: TemplateDetailFormatter.FormattedDetail,
        separator: String,
    ) {
        if detail.macros.isEmpty {
            noora.passthrough("Macros: None\n", tab: 1)
            noora.passthrough("\n")
            return
        }

        noora.passthrough("\(.muted(separator))\n", tab: 0)
        noora.passthrough("\(.accent("Macros")) (\(detail.macros.count))\n", tab: 1)
        noora.passthrough("\(.muted(separator))\n", tab: 0)
        noora.passthrough("\n")

        for (index, macro) in detail.macros.enumerated() {
            displayMacro(macro: macro, index: index + 1)
        }
    }

    private func displayMacro(
        macro: TemplateDetailFormatter.FormattedMacro,
        index: Int,
    ) {
        noora.passthrough("\(index). \(.command(macro.flag))\n", tab: 1)
        noora.passthrough("Name:        \(macro.name)\n", tab: 2)
        noora.passthrough("Type:        \(macro.type)\n", tab: 2)
        noora.passthrough("Description: \(macro.description)\n", tab: 2)

        if let defaultValue = macro.defaultValue {
            noora.passthrough("Default:     \(defaultValue)\n", tab: 2)
        }

        if let choices = macro.choices, !choices.isEmpty {
            noora.passthrough("Choices:\n", tab: 2)
            for choice in choices {
                noora.passthrough("- \(choice)\n", tab: 3)
            }
        }

        if let validation = macro.validation {
            noora.passthrough("Validation:  \(validation)\n", tab: 2)
        }

        noora.passthrough("\n")
    }

    private func displayExampleCommand(
        detail: TemplateDetailFormatter.FormattedDetail,
        separator: String,
    ) {
        noora.passthrough("\(.muted(separator))\n", tab: 0)
        noora.passthrough("\(.accent("Example Command"))\n", tab: 1)
        noora.passthrough("\(.muted(separator))\n", tab: 0)
        noora.passthrough("\n")
        noora.passthrough("\(.command(detail.exampleCommand))\n", tab: 1)
        noora.passthrough("\n")
    }
}
