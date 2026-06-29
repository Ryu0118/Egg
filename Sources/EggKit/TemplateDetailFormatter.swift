import Foundation

/// Formats template details for display
struct TemplateDetailFormatter {
    init() {}

    /// Formatted output for template detail display
    struct FormattedDetail: Equatable {
        let basicInfo: BasicInfo
        let macros: [FormattedMacro]
        let exampleCommand: String
    }

    /// Basic template information
    struct BasicInfo: Equatable {
        let name: String
        let description: String
        let version: String?
        let locationName: String
        let locationDir: String
        let path: String
    }

    /// Formatted macro information
    struct FormattedMacro: Equatable {
        let name: String
        let flag: String
        let type: String
        let description: String
        let defaultValue: String?
        let choices: [String]?
        let validation: String?
    }

    /// Formats a template for display
    func format(
        template: Template,
        location: TemplateLocationType,
    ) -> FormattedDetail {
        let config = template.config

        let basicInfo = BasicInfo(
            name: config.name,
            description: config.description,
            version: config.version,
            locationName: location.name,
            locationDir: location.dir,
            path: template.path.path,
        )

        let formattedMacros = (config.macros ?? []).map { macro in
            FormattedMacro(
                name: macro.name,
                flag: MacroNameConverter.macroToFlag(macro.name),
                type: macro.type.rawValue,
                description: macro.description,
                defaultValue: macro.default?.stringValue,
                choices: macro.choices,
                validation: macro.validate,
            )
        }

        let exampleCommand = generateExampleCommand(
            templateName: config.name,
            macros: config.macros,
        )

        return FormattedDetail(
            basicInfo: basicInfo,
            macros: formattedMacros,
            exampleCommand: exampleCommand,
        )
    }

    /// Generates an example one-liner command for egg hatch
    func generateExampleCommand(
        templateName: String,
        macros: [Config.Macro]?,
    ) -> String {
        let quotedTemplateName = templateName.contains(" ") ? "\"\(templateName)\"" : templateName
        var commandParts = ["egg", "hatch", quotedTemplateName]

        guard let macros, !macros.isEmpty else {
            return commandParts.joined(separator: " ")
        }

        for macro in macros {
            let flag = MacroNameConverter.macroToFlag(macro.name)
            let exampleValue = generateExampleValue(for: macro)

            switch macro.type {
            case .boolean:
                if exampleValue == "true" {
                    commandParts.append(flag)
                } else {
                    let noFlag = flag.replacingOccurrences(of: "--", with: "--no-")
                    commandParts.append(noFlag)
                }
            case .choices, .array:
                commandParts.append(flag)
                commandParts.append(exampleValue)
            default:
                commandParts.append(flag)
                commandParts.append("\"\(exampleValue)\"")
            }
        }

        return commandParts.joined(separator: " ")
    }

    /// Generates an example value for a macro based on its type and configuration
    func generateExampleValue(for macro: Config.Macro) -> String {
        // Use default value if available
        if let defaultValue = macro.default {
            // For array/choices type, convert to space-separated values
            if macro.type == .array || macro.type == .choices {
                return defaultValue.arrayValue.joined(separator: " ")
            }
            return defaultValue.stringValue
        }

        // Use first choice if available
        if let choices = macro.choices, let first = choices.first {
            if macro.type == .choices {
                // For multiple choices, show first two if available
                return choices.prefix(2).joined(separator: " ")
            }
            return first
        }

        // Generate type-appropriate placeholder
        return switch macro.type {
        case .string:
            "value"
        case .boolean:
            "true"
        case .choice:
            "option"
        case .choices:
            "option1 option2"
        case .array:
            "item1 item2"
        case .path:
            "./path/to/file"
        }
    }
}
