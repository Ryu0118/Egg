import Foundation
import Interaction

/// Displays formatted template details to the console
struct TemplateDetailDisplayer {
    private let interaction: any InteractionProviding
    private let formatter = TemplateDetailFormatter()

    init(interaction: some InteractionProviding = Terminal()) {
        self.interaction = interaction
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
        interaction.writeLine("\(separator)", tab: 0)
        interaction.writeLine("\(detail.basicInfo.name)", tab: 1)
        interaction.writeLine("\(separator)", tab: 0)
    }

    private func displayBasicInfo(detail: TemplateDetailFormatter.FormattedDetail) {
        interaction.writeLine("Description:  \(detail.basicInfo.description)", tab: 1)

        if let version = detail.basicInfo.version {
            interaction.writeLine("Version:      \(version)", tab: 1)
        }

        interaction.writeLine("Location:     \(detail.basicInfo.locationName) (\(detail.basicInfo.locationDir))", tab: 1)
        interaction.writeLine("Path:         \(detail.basicInfo.path)", tab: 1)
        interaction.writeLine()
    }

    private func displayMacros(
        detail: TemplateDetailFormatter.FormattedDetail,
        separator: String,
    ) {
        if detail.macros.isEmpty {
            interaction.writeLine("Macros: None", tab: 1)
            interaction.writeLine()
            return
        }

        interaction.writeLine("\(separator)", tab: 0)
        interaction.writeLine("Macros (\(detail.macros.count))", tab: 1)
        interaction.writeLine("\(separator)", tab: 0)
        interaction.writeLine()

        for (index, macro) in detail.macros.enumerated() {
            displayMacro(macro: macro, index: index + 1)
        }
    }

    private func displayMacro(
        macro: TemplateDetailFormatter.FormattedMacro,
        index: Int,
    ) {
        interaction.writeLine("\(index). \(macro.flag)", tab: 1)
        interaction.writeLine("Name:        \(macro.name)", tab: 2)
        interaction.writeLine("Type:        \(macro.type)", tab: 2)
        interaction.writeLine("Description: \(macro.description)", tab: 2)

        if let defaultValue = macro.defaultValue {
            interaction.writeLine("Default:     \(defaultValue)", tab: 2)
        }

        if let choices = macro.choices, !choices.isEmpty {
            interaction.writeLine("Choices:", tab: 2)
            for choice in choices {
                interaction.writeLine("- \(choice)", tab: 3)
            }
        }

        if let validation = macro.validation {
            interaction.writeLine("Validation:  \(validation)", tab: 2)
        }

        interaction.writeLine()
    }

    private func displayExampleCommand(
        detail: TemplateDetailFormatter.FormattedDetail,
        separator: String,
    ) {
        interaction.writeLine("\(separator)", tab: 0)
        interaction.writeLine("Example Command", tab: 1)
        interaction.writeLine("\(separator)", tab: 0)
        interaction.writeLine()
        interaction.writeLine("\(detail.exampleCommand)", tab: 1)
        interaction.writeLine()
    }
}
