import ArgumentParser
import EggKit
import FileManagerProtocol
import Foundation

package extension EggCommand.TemplateCommand {
    struct UpdateCommand: AsyncParsableCommand, HasProjectDirectory {
        @Flag(name: .long, help: "Update only the global manifest ($XDG_CONFIG_HOME/egg/eggs.yml).")
        package var global: Bool = false

        @Flag(name: .long, help: "Update only the project manifest (./eggs.yml).")
        package var project: Bool = false

        @Flag(name: .long, help: "Resolve versions and report without installing or writing the lockfile.")
        package var dryRun: Bool = false

        @Flag(name: .long, help: "Emit machine-readable JSON on stdout instead of the human-readable output.")
        package var json: Bool = false

        @Option(name: .long, help: "Project directory.", completion: .directory)
        package var projectDirectory: String?

        package static let configuration = CommandConfiguration(
            commandName: "update",
            abstract: "Re-resolve eggs.yml to the latest eligible versions and rewrite eggs-lock.yml.",
            discussion: """
            Like 'egg template sync', but ignores locked resolutions:
            'from:' ranges move to the highest satisfying version, and
            'branch:' entries move to the branch tip. The new resolutions
            are recorded in eggs-lock.yml.
            """,
        )

        package static let fileManager: any FileManagerProtocol = FileManager.default

        package init() {}

        package mutating func run() async throws {
            try await ManifestSyncCLI.run(
                mode: .update,
                global: global,
                project: project,
                dryRun: dryRun,
                json: json,
                projectDirectory: resolveProjectDirectory(),
                fileManager: Self.fileManager,
            )
        }
    }
}
