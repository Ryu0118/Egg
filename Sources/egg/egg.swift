import ArgumentParser
import Foundation

@main
struct Egg: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "egg",
        abstract: "A template engine for generating files and folders from templates.",
        subcommands: [
            TemplateCommand.self,
            HatchCommand.self,
        ]
    )
}
