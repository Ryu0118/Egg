import ArgumentParser
import Foundation

package struct EggCommand: AsyncParsableCommand {
    package static let configuration = CommandConfiguration(
        commandName: "egg",
        abstract: "A highly customizable scaffolding tool with scriptable pre and post generation workflows",
        subcommands: [
            TemplateCommand.self,
            HatchCommand.self,
        ]
    )

    package init() {}
}

package extension EggCommand {
    struct TemplateCommand: AsyncParsableCommand {
        package static let configuration = CommandConfiguration(
            commandName: "template",
            abstract: "Manage templates.",
            subcommands: [
                CreateCommand.self,
                ListCommand.self,
                DeleteCommand.self,
                DuplicateCommand.self,
                OpenCommand.self,
            ]
        )

        package init() {}
    }
}
