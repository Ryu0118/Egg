import ArgumentParser
import EggKit
import FileManagerProtocol
import Foundation

package extension EggCommand.TemplateCommand {
    struct InstallCommand: AsyncParsableCommand, HasProjectDirectory {
        @Argument(help: "Git repository URL or local directory path.")
        package var url: String?

        @Flag(name: [.short, .long], help: "Install globally.")
        package var global: Bool = false

        @Flag(name: [.short, .long], help: "Overwrite existing templates.")
        package var force: Bool = false

        @Option(name: [.short, .long], help: "Install from specific branch (Git sources only).")
        package var branch: String?

        @Option(name: [.short, .long], help: "Install from specific tag (Git sources only).")
        package var tag: String?

        @Option(name: [.short, .long], help: "Install from specific commit (Git sources only).")
        package var revision: String?

        @Option(name: .long, parsing: .upToNextOption, help: "Install only specified templates (can be repeated).")
        package var template: [String] = []

        @Option(name: .long, parsing: .upToNextOption, help: "Exclude specified templates (can be repeated).")
        package var exclude: [String] = []

        @Option(name: .long, help: "Project directory.", completion: .directory)
        package var projectDirectory: String?

        @Flag(name: .long, help: "Emit machine-readable JSON on stdout instead of the human-readable output. Requires a source URL/path, and overwrites existing templates.")
        package var json = false

        package static let configuration = CommandConfiguration(
            commandName: "install",
            abstract: "Install templates from a Git repository or local directory.",
            discussion: """
            This command supports two modes:

            Interactive Mode:
              When no source is provided, you will be prompted to enter:
              - Git repository URL or local path
              - Branch, tag, or commit (optional, for Git sources)
              - Installation location (global or project)
              - Templates to install

            Direct Mode:
              Provide the source and options via command-line arguments.

              From Git repository:
                egg template install https://github.com/user/repo.git --tag v1.0.0 --global

              From local directory:
                egg template install ./my-templates --global
                egg template install ~/Projects/templates
                egg template install /path/to/templates

            Recognized source layouts (same for Git and local sources):
              <dir>/config.yml            the directory itself is one template
              <dir>/<name>/config.yml     one template per subdirectory
              <dir>/.eggs/<name>/config.yml   a project checkout's own templates

            Note: --branch, --tag, and --revision options are only valid for Git sources.
            """,
        )

        package static let fileManager: any FileManagerProtocol = FileManager.default

        package init() {}

        package mutating func run() async throws {
            if json {
                guard let url else {
                    throw ValidationError("--json requires a source URL or path (interactive prompts need a TTY).")
                }
                guard [branch, tag, revision].compactMap(\.self).count <= 1 else {
                    throw ValidationError("Only one of --branch, --tag, or --revision can be specified.")
                }
                let result = try await EggService(
                    fileManager: Self.fileManager,
                    projectDirectory: resolveProjectDirectory(),
                    homeDirectory: CLIEnvironment.resolveHomeDirectory(),
                ).installTemplates(
                    source: url,
                    location: global ? "global" : "project",
                    ref: branch ?? tag ?? revision,
                    include: template.isEmpty ? nil : template,
                    exclude: exclude.isEmpty ? nil : exclude,
                )
                try CLIOutput.printJSON(result.encoded)
                return
            }
            let mode = try await validate()
            do {
                let result = try await InstallRunner(
                    mode: mode,
                    force: force,
                    projectDirectory: resolveProjectDirectory(),
                    workingDirectory: URL(filePath: Self.fileManager.currentDirectoryPath),
                    homeDirectory: CLIEnvironment.resolveHomeDirectory(),
                    fileManager: Self.fileManager,
                ).run()

                // Display summary
                displaySummary(result)

                // Throw error if no templates were installed
                if result.installed.isEmpty {
                    throw InstallError.allTemplatesSkippedOrFailed
                }
            } catch let error as InstallError {
                CLIOutput.printError(error.errorDescription ?? error.localizedDescription)
                throw ExitCode.failure
            } catch {
                CLIOutput.printError(error.localizedDescription)
                throw ExitCode.failure
            }
        }

        func validate() async throws -> InstallRunnerMode {
            do {
                let projectDirectory = try await resolveProjectDirectory()
                let workingDirectory = URL(filePath: Self.fileManager.currentDirectoryPath)
                return try await InstallArgumentsValidator(
                    url: url,
                    branch: branch,
                    tag: tag,
                    revision: revision,
                    templates: template,
                    excludeTemplates: exclude,
                    global: global,
                    projectDirectory: projectDirectory,
                    workingDirectory: workingDirectory,
                    homeDirectory: CLIEnvironment.resolveHomeDirectory(),
                ).validate()
            } catch {
                throw ValidationError(error.localizedDescription)
            }
        }

        private func displaySummary(_ result: InstallResult) {
            if !result.installed.isEmpty {
                CLIOutput.printSuccess("Successfully installed \(result.installed.count) template(s).")
            }

            if !result.skipped.isEmpty {
                let skippedCount = result.skipped.count
                CLIOutput.printWarning("Skipped \(skippedCount) template(s).")
            }

            if !result.failed.isEmpty {
                let failedCount = result.failed.count
                CLIOutput.printError("Failed to install \(failedCount) template(s).")
            }
        }
    }
}

/// Errors specific to the install command.
enum InstallError: LocalizedError {
    case allTemplatesSkippedOrFailed

    var errorDescription: String? {
        switch self {
        case .allTemplatesSkippedOrFailed:
            "No templates were installed. All templates were either skipped or failed."
        }
    }
}
