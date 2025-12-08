import ArgumentParser
import Foundation

@main
package struct EggCommand: AsyncParsableCommand {
    package static let configuration = CommandConfiguration(
        commandName: "egg",
        abstract: "A template engine for generating files and folders from templates.",
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
