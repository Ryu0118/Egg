import Foundation
import ArgumentParser

@main
struct Egg: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "egg",
        abstract: "A template engine for generating files and folders from templates.",
        subcommands: [
            Template.self,
            Hatch.self
        ]
    )
}
