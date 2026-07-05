import Foundation
import Interaction

/// Displays formatted template details to the console
struct TemplateDetailDisplayer {
    private let interaction: any InteractionProviding
    private let formatter = TemplateDetailFormatter()

    init(interaction: some InteractionProviding = GuardedTerminal()) {
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
        interaction.writeLine("\(StyledText.Segment.muted(separator))", tab: 0)
        interaction.writeLine("\(StyledText.Segment.primary(detail.basicInfo.name))", tab: 1)
        interaction.writeLine("\(StyledText.Segment.muted(separator))", tab: 0)
    }

    private func displayBasicInfo(detail: TemplateDetailFormatter.FormattedDetail) {
        interaction.writeLine("\(StyledText.Segment.muted("Description:")) \(detail.basicInfo.description)", tab: 1)

        if let version = detail.basicInfo.version {
            interaction.writeLine("\(StyledText.Segment.muted("Version:")) \(version)", tab: 1)
        }

        interaction.writeLine(
            "\(StyledText.Segment.muted("Location:")) \(detail.basicInfo.locationName) (\(detail.basicInfo.locationDir))",
            tab: 1,
        )
        interaction.writeLine("\(StyledText.Segment.muted("Path:")) \(StyledText.Segment.path(detail.basicInfo.path))", tab: 1)
        interaction.writeLine()
    }

    private func displayMacros(
        detail: TemplateDetailFormatter.FormattedDetail,
        separator: String,
    ) {
        if detail.macros.isEmpty {
            interaction.writeLine("\(StyledText.Segment.muted("Macros: None"))", tab: 1)
            interaction.writeLine()
            return
        }

        interaction.writeLine("\(StyledText.Segment.muted(separator))", tab: 0)
        interaction.writeLine("\(StyledText.Segment.primary("Macros (\(detail.macros.count))"))", tab: 1)
        interaction.writeLine("\(StyledText.Segment.muted(separator))", tab: 0)
        interaction.writeLine()

        for (index, macro) in detail.macros.enumerated() {
            displayMacro(macro: macro, index: index + 1)
        }
    }

    private func displayMacro(
        macro: TemplateDetailFormatter.FormattedMacro,
        index: Int,
    ) {
        interaction.writeLine("\(StyledText.Segment.accent("\(index). \(macro.flag)"))", tab: 1)
        interaction.writeLine("\(StyledText.Segment.muted("Name:")) \(macro.name)", tab: 2)
        interaction.writeLine("\(StyledText.Segment.muted("Type:")) \(macro.type)", tab: 2)
        interaction.writeLine("\(StyledText.Segment.muted("Description:")) \(macro.description)", tab: 2)

        if let defaultValue = macro.defaultValue {
            interaction.writeLine("\(StyledText.Segment.muted("Default:")) \(defaultValue)", tab: 2)
        }

        if let choices = macro.choices, !choices.isEmpty {
            interaction.writeLine("\(StyledText.Segment.muted("Choices:"))", tab: 2)
            for choice in choices {
                interaction.writeLine("- \(choice)", tab: 3)
            }
        }

        if let validation = macro.validation {
            interaction.writeLine("\(StyledText.Segment.muted("Validation:")) \(validation)", tab: 2)
        }

        interaction.writeLine()
    }

    private func displayExampleCommand(
        detail: TemplateDetailFormatter.FormattedDetail,
        separator: String,
    ) {
        interaction.writeLine("\(StyledText.Segment.muted(separator))", tab: 0)
        interaction.writeLine("\(StyledText.Segment.primary("Example Command"))", tab: 1)
        interaction.writeLine("\(StyledText.Segment.muted(separator))", tab: 0)
        interaction.writeLine()
        interaction.writeLine("\(StyledText.Segment.command(detail.exampleCommand))", tab: 1)
        interaction.writeLine()
    }
}
